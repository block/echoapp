package com.squareup.moshix.sealedswiftcompat

import com.google.auto.service.AutoService
import com.google.devtools.ksp.KspExperimental
import com.google.devtools.ksp.getAnnotationsByType
import com.google.devtools.ksp.processing.Dependencies
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.processing.SymbolProcessorEnvironment
import com.google.devtools.ksp.processing.SymbolProcessorProvider
import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.Modifier
import com.squareup.kotlinpoet.ClassName
import com.squareup.kotlinpoet.asClassName
import com.squareup.kotlinpoet.ksp.toClassName
import com.squareup.moshi.JsonClass
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.codegen.api.InternalMoshiCodegenApi
import com.squareup.moshi.kotlin.codegen.api.ProguardConfig
import com.squareup.moshix.sealedswiftcompat.SealedSwiftCompatProguardRuleGenProcessorProvider.Companion.MOSHI_GENERATOR_NAME
import kotlin.sequences.forEach

@AutoService(SymbolProcessorProvider::class)
class SealedSwiftCompatProguardRuleGenProcessorProvider : SymbolProcessorProvider {
  override fun create(environment: SymbolProcessorEnvironment): SymbolProcessor {
    return SealedSwiftCompatProguardRuleGenProcessor(environment)
  }

  internal companion object {
    const val MOSHI_GENERATOR_NAME = "sealed-swift-compat"
  }
}

/**
 * Modified version of
 * [https://github.com/ZacSweers/MoshiX/blob/main/moshi-proguard-rule-gen/src/main/kotlin/dev/zacsweers/moshix/proguardgen/MoshiProguardGenSymbolProcessor.kt].
 *
 * Big shout out to @zacsweers for his work!
 */
private class SealedSwiftCompatProguardRuleGenProcessor(
    environment: SymbolProcessorEnvironment,
) : SymbolProcessor {
  private companion object {
    val JSON_CLASS_NAME = JsonClass::class.qualifiedName!!
    val MOSHI_REFLECTIVE_NAME = Moshi::class.asClassName().reflectionName()
    val TYPE_ARRAY_REFLECTIVE_NAME =
        "${java.lang.reflect.Type::class.asClassName().reflectionName()}[]"
  }

  private val codeGenerator = environment.codeGenerator
  private val logger = environment.logger

  @OptIn(KspExperimental::class, InternalMoshiCodegenApi::class)
  override fun process(resolver: Resolver): List<KSAnnotated> {
    resolver
        .getSymbolsWithAnnotation(JSON_CLASS_NAME)
        .mapNotNull {
          if (it !is KSClassDeclaration) {
            // Don't worry about erroring here, the real generator will do it
            return@mapNotNull null
          }
          it to it.getAnnotationsByType(JsonClass::class).single()
        }
        .filter { (_, annotation) -> annotation.generateAdapter }
        .forEach { (clazz, jsonClass) ->
          val generatorKey = jsonClass.generator
          val isMoshiSealed = generatorKey == MOSHI_GENERATOR_NAME
          val clazzName = clazz.toClassName()

          if (isMoshiSealed) {
            val targetType = clazzName
            val hasGenerics = clazz.typeParameters.isNotEmpty()
            val adapterName = "${targetType.simpleNames.joinToString(separator = "_")}JsonAdapter"
            val adapterConstructorParams =
                when (hasGenerics) {
                  false -> listOf(MOSHI_REFLECTIVE_NAME)
                  true -> listOf(MOSHI_REFLECTIVE_NAME, TYPE_ARRAY_REFLECTIVE_NAME)
                }

            val nestedSealedClassNames: Set<ClassName>
            if (clazz.isSealed) {
              nestedSealedClassNames = mutableSetOf()
              clazz.walkSealedSubtypes(nestedSealedClassNames)
            } else {
              nestedSealedClassNames = setOf(clazzName)
            }

            val config =
                ProguardConfig(
                    targetClass = targetType,
                    adapterName = adapterName,
                    adapterConstructorParams = adapterConstructorParams,
                    // Not actually true but in our case we don't need the generated rules for this
                    targetConstructorHasDefaults = false,
                    targetConstructorParams = emptyList(),
                )

            logger.info(
                "MOSHI: Writing proguard rules for ${targetType.canonicalName}: $config",
                clazz,
            )
            val fileName = config.outputFilePathWithoutExtension(targetType.canonicalName)
            codeGenerator
                .createNewFile(
                    Dependencies(
                        aggregating = false,
                        sources = clazz.containingFile?.let { arrayOf(it) }.orEmpty(),
                    ),
                    packageName = "",
                    fileName = fileName,
                    extensionName = "pro",
                )
                .bufferedWriter()
                .use { writer ->
                  if (nestedSealedClassNames.isNotEmpty()) {
                    val adapterReflectionName =
                        ClassName(targetType.packageName, adapterName).reflectionName()
                    for (target in nestedSealedClassNames.sorted()) {
                      val targetReflectionName = target.reflectionName()
                      writer.appendLine("-if class $targetReflectionName")
                      writer.appendLine("-keep class $adapterReflectionName {")
                      // Keep the constructor for Moshi's reflective lookup
                      val constructorArgs = adapterConstructorParams.joinToString(",")
                      writer.appendLine("    public <init>($constructorArgs);")
                      writer.appendLine("}")
                    }
                  }
                }
          }
        }
    return emptyList()
  }

  private val KSClassDeclaration.isSealed: Boolean
    get() = Modifier.SEALED in modifiers

  private fun KSClassDeclaration.walkSealedSubtypes(elements: MutableSet<ClassName>) {
    if (isSealed) {
      elements += toClassName()
      for (nested in getSealedSubclasses()) {
        nested.walkSealedSubtypes(elements)
      }
    } else {
      elements += toClassName()
    }
  }
}
