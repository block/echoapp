package com.squareup.moshix.sealedswiftcompat.generators

import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.symbol.ClassKind.CLASS
import com.google.devtools.ksp.symbol.ClassKind.OBJECT
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.Modifier.SEALED
import com.squareup.kotlinpoet.ClassName
import com.squareup.kotlinpoet.FileSpec
import com.squareup.kotlinpoet.FunSpec
import com.squareup.kotlinpoet.KModifier.INTERNAL
import com.squareup.kotlinpoet.KModifier.OVERRIDE
import com.squareup.kotlinpoet.KModifier.PUBLIC
import com.squareup.kotlinpoet.ParameterizedTypeName.Companion.parameterizedBy
import com.squareup.kotlinpoet.TypeSpec
import com.squareup.kotlinpoet.asClassName
import com.squareup.kotlinpoet.ksp.addOriginatingKSFile
import com.squareup.kotlinpoet.ksp.toClassName
import com.squareup.kotlinpoet.ksp.writeTo
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.Moshi
import com.squareup.moshix.sealedswiftcompat.utils.MoshiSealedSymbols
import com.squareup.moshix.sealedswiftcompat.utils.adapterPropertyName
import com.squareup.moshix.sealedswiftcompat.utils.addJsonAdapterProperty
import com.squareup.moshix.sealedswiftcompat.utils.addSuppressions
import com.squareup.moshix.sealedswiftcompat.utils.findAnnotationWithType
import com.squareup.moshix.sealedswiftcompat.utils.isSealedSwiftCompatEnabled
import com.squareup.moshix.sealedswiftcompat.utils.jsonName
import com.squareup.moshix.sealedswiftcompat.utils.moshiAdapterName

internal class SealedAdapterCodeGenerator(
    private val generator: CodeGenerator,
    private val logger: KSPLogger,
    private val symbols: MoshiSealedSymbols,
    private val subAdapterCodeGenerator: SubAdapterCodeGenerator,
) {
  fun generate(
      targetType: KSClassDeclaration,
      isInternal: Boolean,
  ) {
    if (SEALED !in targetType.modifiers) {
      logger.error("Can't generate adapter for non-sealed type: $targetType", targetType)
      return
    }

    val targetTypeName = targetType.toClassName()
    val adapterName = targetTypeName.moshiAdapterName()
    val neededJsonAdapters = mutableSetOf<ClassName>()

    val fromJsonBuilder =
        FunSpec.builder("fromJson")
            .addModifiers(OVERRIDE)
            .addParameter("reader", JsonReader::class)
            .returns(targetTypeName.copy(nullable = true))
            .addStatement("reader.beginObject()")
            .addStatement("val name = reader.nextName()")
            .beginControlFlow("val result = when (name) {")

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
                writer.beginObject()
                """
                    .trimIndent(),
            )
            .beginControlFlow("\nwhen (value_) {")

    targetType.getSealedSubclasses().forEach { subType ->
      val subTypeName = subType.toClassName()
      val subTypeJsonName = subType.jsonName(symbols) ?: subType.simpleName.asString()
      fromJsonBuilder.addCode("%S -> ", subTypeJsonName)
      toJsonBuilder.addCode("is %T -> ", subTypeName)

      when (val classKind = subType.classKind) {
        OBJECT -> {
          fromJsonBuilder.run {
            beginControlFlow("{")
            addStatement("reader.skipValue()")
            addStatement("%T", subTypeName)
            endControlFlow()
          }
          toJsonBuilder.run {
            beginControlFlow("{")
            addStatement("writer.name(%S)", subTypeJsonName)
            addStatement("writer.beginObject()")
            addStatement("writer.endObject()")
            endControlFlow()
          }
        }
        CLASS -> {
          if (subType.findAnnotationWithType(symbols.jsonClass).isSealedSwiftCompatEnabled()) {
            subAdapterCodeGenerator.generate(
                targetType = subType,
                isInternal = isInternal,
            )
          }
          val adapterPropertyName = subTypeName.adapterPropertyName()
          fromJsonBuilder.addCode("%L.fromJson(reader)\n", adapterPropertyName)
          toJsonBuilder.run {
            beginControlFlow("{")
            addStatement("writer.name(%S)", subTypeJsonName)
            addCode("%L.toJson(writer, value_)\n", adapterPropertyName)
            endControlFlow()
          }
          neededJsonAdapters += subTypeName
        }
        else -> logger.error("Can't handle property class kind: $classKind", targetType)
      }
    }

    fromJsonBuilder
        .beginControlFlow("else -> {")
        .addStatement("reader.skipValue()")
        .addStatement("null")
        .endControlFlow()
        .endControlFlow()
        .addStatement("reader.endObject()")
        .addStatement("return result")
    toJsonBuilder.endControlFlow().addStatement("writer.endObject()")

    val classBuilder =
        TypeSpec.classBuilder(adapterName)
            .addModifiers(if (isInternal) INTERNAL else PUBLIC)
            .superclass(
                JsonAdapter::class.asClassName().parameterizedBy(targetTypeName),
            )
            .addSuppressions()
            .primaryConstructor(
                FunSpec.constructorBuilder().addParameter("moshi", Moshi::class).build(),
            )
            .apply { neededJsonAdapters.forEach { addJsonAdapterProperty(it) } }
            .addFunction(fromJsonBuilder.build())
            .addFunction(toJsonBuilder.build())
            .addOriginatingKSFile(targetType.containingFile!!)

    val file =
        FileSpec.builder(targetTypeName.packageName, adapterName)
            .indent("  ")
            .addFileComment("Code generated by moshi-sealed-swift-compat. Do not edit.")
            .addType(classBuilder.build())
            .build()
    file.writeTo(generator, aggregating = true)
  }
}
