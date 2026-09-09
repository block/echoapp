package com.squareup.moshix.sealedswiftcompat.utils

import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.devtools.ksp.symbol.KSAnnotation
import com.squareup.kotlinpoet.AnnotationSpec
import com.squareup.kotlinpoet.ClassName
import com.squareup.kotlinpoet.CodeBlock
import com.squareup.kotlinpoet.KModifier.PRIVATE
import com.squareup.kotlinpoet.ParameterizedTypeName
import com.squareup.kotlinpoet.ParameterizedTypeName.Companion.parameterizedBy
import com.squareup.kotlinpoet.PropertySpec
import com.squareup.kotlinpoet.TypeName
import com.squareup.kotlinpoet.TypeSpec
import com.squareup.kotlinpoet.WildcardTypeName
import com.squareup.kotlinpoet.asTypeName
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Types
import com.squareup.moshix.sealedswiftcompat.MoshiSealedSwiftCompatProcessorProvider.Companion.MOSHI_GENERATOR_NAME

internal fun KSAnnotation?.isSealedSwiftCompatEnabled(): Boolean {
  return if (this == null || !getMember<Boolean>("generateAdapter")) {
    false
  } else {
    getMember<String>("generator") == MOSHI_GENERATOR_NAME
  }
}

internal fun KSAnnotated.jsonName(symbols: MoshiSealedSymbols): String? =
    findAnnotationWithType(symbols.json)?.getMember<String>("name")

internal fun ClassName.moshiAdapterName(): String {
  return ClassName.bestGuess(
          Types.generatedJsonAdapterName(reflectionName()),
      )
      .simpleName
}

internal fun TypeName.adapterPropertyName(): String {
  return when (this) {
    is ParameterizedTypeName -> {
      val rawTypeName = rawType.simpleName.lowercase()
      val argumentNames =
          typeArguments.joinToString(separator = "") {
            if (it is WildcardTypeName) "Any" else (it as ClassName).simpleName
          }
      "${rawTypeName}Of${argumentNames}Adapter"
    }
    is ClassName -> {
      simpleName.let { it.substring(0, 1).lowercase() + it.substring(1) }.plus("Adapter")
    }
    else -> error("Can't get adapter property name for $this")
  }
}

internal fun TypeSpec.Builder.addSuppressions() = apply {
  addAnnotation(
      AnnotationSpec.builder(Suppress::class)
          .addMember(
              "%S, %S, %S, %S",
              "ClassName",
              "RedundantVisibilityModifier",
              "unused",
              "LocalVariableName",
          )
          .build(),
  )
}

internal fun TypeSpec.Builder.addJsonAdapterProperty(typeName: TypeName) = apply {
  val propertyType = JsonAdapter::class.asTypeName().parameterizedBy(typeName)
  addProperty(
      PropertySpec.builder(typeName.adapterPropertyName(), propertyType, PRIVATE)
          .apply {
            if (typeName is ParameterizedTypeName) {
              initializer(
                  CodeBlock.builder()
                      .add(
                          "moshi.adapter(%T.newParameterizedType(%T::class.java",
                          Types::class,
                          typeName.rawType,
                      )
                      .apply { typeName.typeArguments.forEach { add(", %T::class.java", it) } }
                      .add("))")
                      .build(),
              )
            } else {
              initializer("moshi.adapter(%T::class.java)", typeName)
            }
          }
          .build(),
  )
}
