package com.squareup.moshix.sealedswiftcompat.generators

import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.symbol.ClassKind.CLASS
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.squareup.kotlinpoet.ClassName
import com.squareup.kotlinpoet.CodeBlock
import com.squareup.kotlinpoet.FileSpec
import com.squareup.kotlinpoet.FunSpec
import com.squareup.kotlinpoet.KModifier.INTERNAL
import com.squareup.kotlinpoet.KModifier.OVERRIDE
import com.squareup.kotlinpoet.KModifier.PRIVATE
import com.squareup.kotlinpoet.KModifier.PUBLIC
import com.squareup.kotlinpoet.ParameterizedTypeName.Companion.parameterizedBy
import com.squareup.kotlinpoet.PropertySpec
import com.squareup.kotlinpoet.TypeName
import com.squareup.kotlinpoet.TypeSpec
import com.squareup.kotlinpoet.asClassName
import com.squareup.kotlinpoet.ksp.addOriginatingKSFile
import com.squareup.kotlinpoet.ksp.toClassName
import com.squareup.kotlinpoet.ksp.toTypeName
import com.squareup.kotlinpoet.ksp.writeTo
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.Moshi
import com.squareup.moshi.internal.Util
import com.squareup.moshix.sealedswiftcompat.utils.MoshiSealedSymbols
import com.squareup.moshix.sealedswiftcompat.utils.adapterPropertyName
import com.squareup.moshix.sealedswiftcompat.utils.addJsonAdapterProperty
import com.squareup.moshix.sealedswiftcompat.utils.addSuppressions
import com.squareup.moshix.sealedswiftcompat.utils.jsonName
import com.squareup.moshix.sealedswiftcompat.utils.moshiAdapterName
import com.squareup.moshix.sealedswiftcompat.utils.unwrapTypeAlias

internal class SubAdapterCodeGenerator(
    private val generator: CodeGenerator,
    private val logger: KSPLogger,
    private val symbols: MoshiSealedSymbols,
    private val generatedAdaptersForTypes: MutableSet<ClassName>,
) {
  fun generate(
      targetType: KSClassDeclaration,
      isInternal: Boolean,
  ) {
    if (targetType.classKind != CLASS) {
      logger.error("Can't generate adapter for non-class type: $targetType", targetType)
      return
    }
    val primaryConstructor =
        targetType.primaryConstructor
            ?: run {
              logger.error("Class missing primary constructor: $targetType", targetType)
              return
            }

    val targetTypeName = targetType.toClassName()
    if (targetTypeName in generatedAdaptersForTypes) return
    generatedAdaptersForTypes += targetTypeName

    val adapterName = targetTypeName.moshiAdapterName()
    val neededJsonAdapters = mutableSetOf<TypeName>()

    val cachedProperties =
        primaryConstructor.parameters.mapIndexed { index, parameter ->
          val name = parameter.name!!.asString()
          val type = parameter.type.resolve().unwrapTypeAlias()
          CachedProperty(
                  codeName = name,
                  jsonName = parameter.jsonName(symbols) ?: "_$index",
                  typeName = type.toTypeName(),
              )
              .also { neededJsonAdapters += it.typeName }
        }

    val classBuilder =
        TypeSpec.classBuilder(adapterName)
            .addModifiers(if (isInternal) INTERNAL else PUBLIC)
            .superclass(
                JsonAdapter::class.asClassName().parameterizedBy(targetTypeName),
            )
            .addSuppressions()
            .addOriginatingKSFile(targetType.containingFile!!)

    val fromJsonBuilder =
        FunSpec.builder("fromJson")
            .addModifiers(OVERRIDE)
            .addParameter("reader", JsonReader::class)
            .returns(targetTypeName)

    val toJsonBuilder =
        FunSpec.builder("toJson")
            .addModifiers(OVERRIDE)
            .addParameter("writer", JsonWriter::class)
            .addParameter("value_", targetTypeName.copy(nullable = true))
            .addCode(
                """
                if (value_ == null) {
                  throw NullPointerException("value_ was null! Wrap in .nullSafe() to write nullable values.")
                }
                """
                    .trimIndent(),
            )
            .addCode("\n")

    val optionsPropertyCode = CodeBlock.builder().add("%T.of(", JsonReader.Options::class)
    cachedProperties.forEachIndexed { index, cachedProperty ->
      fromJsonBuilder.addStatement(
          "var %L: %T? = null",
          cachedProperty.codeName,
          cachedProperty.typeName,
      )
      if (index > 0) optionsPropertyCode.add(", ")
      optionsPropertyCode.add("%S", cachedProperty.jsonName)
    }
    optionsPropertyCode.add(")")

    fromJsonBuilder.run {
      addStatement("reader.beginObject()")
      beginControlFlow("while (reader.hasNext()) {")
      beginControlFlow("when (reader.selectName(options)) {")
      cachedProperties.forEachIndexed { index, cachedProperty ->
        addStatement(
            "%L -> %L = %L.fromJson(reader) ?: throw %T.unexpectedNull(%S, %S, reader)",
            index,
            cachedProperty.codeName,
            cachedProperty.typeName.adapterPropertyName(),
            Util::class,
            cachedProperty.codeName,
            cachedProperty.jsonName,
        )
      }
      addCode(
          """
          -1 -> {
            // Unknown name, skip it.
            reader.skipName()
            reader.skipValue()
          }
          """
              .trimIndent(),
      )
      addCode("\n")
      endControlFlow()
      endControlFlow()
      addStatement("reader.endObject()")
      addCode("return %T(\n", targetTypeName)
      cachedProperties.forEach { cachedProperty ->
        addStatement(
            "  %L = %L ?: throw %T.missingProperty(%S, %S, reader),",
            cachedProperty.codeName,
            cachedProperty.codeName,
            Util::class,
            cachedProperty.codeName,
            cachedProperty.jsonName,
        )
      }
      addCode(")")
    }

    toJsonBuilder.run {
      addStatement("writer.beginObject()")
      cachedProperties.forEach { cachedProperty ->
        addStatement("writer.name(%S)", cachedProperty.jsonName)
        addStatement(
            "%L.toJson(writer, value_.%L)",
            cachedProperty.typeName.adapterPropertyName(),
            cachedProperty.codeName,
        )
      }
      addStatement("writer.endObject()")
    }

    classBuilder
        .primaryConstructor(
            FunSpec.constructorBuilder().addParameter("moshi", Moshi::class).build(),
        )
        .addProperty(
            PropertySpec.builder("options", JsonReader.Options::class.java, PRIVATE)
                .initializer(optionsPropertyCode.build())
                .build(),
        )
        .apply { neededJsonAdapters.forEach { addJsonAdapterProperty(it) } }
        .addFunction(fromJsonBuilder.build())
        .addFunction(toJsonBuilder.build())

    val file =
        FileSpec.builder(targetTypeName.packageName, adapterName)
            .indent("  ")
            .addFileComment("Code generated by moshi-sealed-swift-compat. Do not edit.")
            .addType(classBuilder.build())
            .build()
    file.writeTo(generator, aggregating = true)
  }

  private data class CachedProperty(
      val codeName: String,
      val jsonName: String,
      val typeName: TypeName,
  )
}
