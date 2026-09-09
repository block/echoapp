package com.squareup.moshix.sealedswiftcompat

import com.google.common.truth.Truth.assertThat
import com.tschuchort.compiletesting.KotlinCompilation
import com.tschuchort.compiletesting.KotlinCompilation.ExitCode
import com.tschuchort.compiletesting.SourceFile
import com.tschuchort.compiletesting.SourceFile.Companion.kotlin
import com.tschuchort.compiletesting.configureKsp
import com.tschuchort.compiletesting.kspSourcesDir
import java.io.File
import org.junit.Test

/**
 * Based on
 * [https://github.com/ZacSweers/MoshiX/blob/main/moshi-sealed/codegen/src/test/kotlin/dev/zacsweers/moshix/sealed/codegen/ksp/MoshiSealedSymbolProcessorTest.kt].
 */
class SealedSwiftCompatProguardRuleGenProcessorTest {
  companion object {
    val DATA_CLASS =
        kotlin(
            "MyClass.kt",
            """
            package com.example

            import com.squareup.moshi.Json
            import com.squareup.moshi.JsonClass

            @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
            data class MyClass(
              val test: String,
              val test2: Int,
              val test3: Boolean,
              val test4: List<String>,
              val test5: EnumOne,
            )
            """
                .trimIndent(),
        )
    val ENUM_CLASSES =
        kotlin(
            "Enums.kt",
            """
            package com.example

            import com.squareup.moshi.Json

            enum class EnumOne {
              One,
              Two
            }

            enum class EnumTwo {
              @Json(name = "1")
              One,
              @Json(name = "2")
              Two
            }
            """
                .trimIndent(),
        )
    val SEALED_INTERFACE =
        kotlin(
            "TestInterface.kt",
            """
            package com.example

            import com.squareup.moshi.Json
            import com.squareup.moshi.JsonClass

            @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
            sealed interface TestInterface {
              @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
              data class TestA(
                val a: Int,
                val b: EnumOne,
                val c: MyClass,
              ) : TestInterface

              @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
              data class TestB(val b: String) : TestInterface

              data object TestC : TestInterface
            }
            """
                .trimIndent(),
        )
  }

  @Test
  fun topLevelDataClass() {
    val compilation = prepareCompilation(ENUM_CLASSES, DATA_CLASS)
    val result = compilation.compile()
    assertThat(result.exitCode).isEqualTo(ExitCode.OK)

    val generatedSourcesDir = compilation.kspSourcesDir
    val proguardFiles = generatedSourcesDir.walkTopDown().filter { it.extension == "pro" }.toList()
    assertThat(proguardFiles.map { it.name }).containsExactly("moshi-com.example.MyClass.pro")
    for (generatedFile in proguardFiles) {
      generatedFile.assertInCorrectPath()
      when (generatedFile.nameWithoutExtension) {
        "moshi-com.example.MyClass" -> {
          assertThat(generatedFile.readText().trimIndent())
              .isEqualTo(
                  """
                  -if class com.example.MyClass
                  -keep class com.example.MyClassJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  """
                      .trimIndent(),
              )
        }
        else -> error("Unhandled proguard file: $generatedFile")
      }
    }
  }

  @Test
  fun sealedInterface() {
    val compilation = prepareCompilation(ENUM_CLASSES, DATA_CLASS, SEALED_INTERFACE)
    val result = compilation.compile()
    assertThat(result.exitCode).isEqualTo(ExitCode.OK)

    val generatedSourcesDir = compilation.kspSourcesDir
    val proguardFiles = generatedSourcesDir.walkTopDown().filter { it.extension == "pro" }.toList()
    assertThat(proguardFiles.map { it.name })
        .containsExactly(
            "moshi-com.example.MyClass.pro",
            "moshi-com.example.TestInterface.pro",
            "moshi-com.example.TestInterface.TestA.pro",
            "moshi-com.example.TestInterface.TestB.pro",
        )
    for (generatedFile in proguardFiles) {
      generatedFile.assertInCorrectPath()
      when (generatedFile.nameWithoutExtension) {
        "moshi-com.example.TestInterface" -> {
          assertThat(generatedFile.readText().trimIndent())
              .isEqualTo(
                  """
                  -if class com.example.TestInterface
                  -keep class com.example.TestInterfaceJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  -if class com.example.TestInterface${'$'}TestA
                  -keep class com.example.TestInterfaceJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  -if class com.example.TestInterface${'$'}TestB
                  -keep class com.example.TestInterfaceJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  -if class com.example.TestInterface${'$'}TestC
                  -keep class com.example.TestInterfaceJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  """
                      .trimIndent(),
              )
        }
        "moshi-com.example.MyClass" -> {
          assertThat(generatedFile.readText().trimIndent())
              .isEqualTo(
                  """
                  -if class com.example.MyClass
                  -keep class com.example.MyClassJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  """
                      .trimIndent(),
              )
        }
        "moshi-com.example.TestInterface.TestA" -> {
          assertThat(generatedFile.readText().trimIndent())
              .isEqualTo(
                  """
                  -if class com.example.TestInterface${'$'}TestA
                  -keep class com.example.TestInterface_TestAJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  """
                      .trimIndent(),
              )
        }
        "moshi-com.example.TestInterface.TestB" -> {
          assertThat(generatedFile.readText().trimIndent())
              .isEqualTo(
                  """
                  -if class com.example.TestInterface${'$'}TestB
                  -keep class com.example.TestInterface_TestBJsonAdapter {
                      public <init>(com.squareup.moshi.Moshi);
                  }
                  """
                      .trimIndent(),
              )
        }
        else -> error("Unhandled proguard file: $generatedFile")
      }
    }
  }

  private fun prepareCompilation(vararg sourceFiles: SourceFile): KotlinCompilation =
      KotlinCompilation().apply {
        sources = sourceFiles.toList()
        inheritClassPath = true
        configureKsp {
          symbolProcessorProviders += SealedSwiftCompatProguardRuleGenProcessorProvider()
        }
        kotlincArguments += "-Xskip-prerelease-check"
      }

  private fun File.assertInCorrectPath() {
    // Ensure the proguard file is in the right place
    // https://github.com/ZacSweers/MoshiX/issues/461
    check(absolutePath.contains("META-INF/proguard/"))
  }
}
