package com.squareup.moshix.sealedswiftcompat

import com.google.auto.service.AutoService
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.processing.SymbolProcessorEnvironment
import com.google.devtools.ksp.processing.SymbolProcessorProvider
import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.Modifier
import com.squareup.kotlinpoet.ClassName
import com.squareup.moshi.JsonClass
import com.squareup.moshix.sealedswiftcompat.generators.SealedAdapterCodeGenerator
import com.squareup.moshix.sealedswiftcompat.generators.SubAdapterCodeGenerator
import com.squareup.moshix.sealedswiftcompat.utils.MoshiSealedSymbols
import com.squareup.moshix.sealedswiftcompat.utils.findAnnotationWithType
import com.squareup.moshix.sealedswiftcompat.utils.isSealedSwiftCompatEnabled

@AutoService(SymbolProcessorProvider::class)
class MoshiSealedSwiftCompatProcessorProvider : SymbolProcessorProvider {
  override fun create(environment: SymbolProcessorEnvironment): SymbolProcessor {
    return MoshiSealedSwiftCompatProcessor(environment)
  }

  internal companion object {
    const val MOSHI_GENERATOR_NAME = "sealed-swift-compat"
  }
}

/**
 * Based on
 * [https://github.com/ZacSweers/MoshiX/blob/main/moshi-sealed/codegen/src/main/kotlin/dev/zacsweers/moshix/sealed/codegen/ksp/MoshiSealedSymbolProcessorProvider.kt].
 *
 * Big shout out to @zacsweers for his work!
 */
private class MoshiSealedSwiftCompatProcessor(
    environment: SymbolProcessorEnvironment,
) : SymbolProcessor {
  private companion object {
    val JSON_CLASS_NAME = JsonClass::class.qualifiedName!!
  }

  private val codeGenerator = environment.codeGenerator
  private val logger = environment.logger

  override fun process(resolver: Resolver): List<KSAnnotated> {
    val symbols = MoshiSealedSymbols(resolver)
    val generatedAdaptersForTypes = mutableSetOf<ClassName>()
    val subAdapterCodeGenerator =
        SubAdapterCodeGenerator(
            generator = codeGenerator,
            logger = logger,
            symbols = symbols,
            generatedAdaptersForTypes = generatedAdaptersForTypes,
        )
    val sealedAdapterCodeGenerator =
        SealedAdapterCodeGenerator(
            generator = codeGenerator,
            logger = logger,
            symbols = symbols,
            subAdapterCodeGenerator = subAdapterCodeGenerator,
        )

    resolver.getSymbolsWithAnnotation(JSON_CLASS_NAME).forEach { type ->
      if (type !is KSClassDeclaration) {
        logger.error("@JsonClass is only applicable to classes!", type)
        return@forEach
      }
      if (!type.findAnnotationWithType(symbols.jsonClass).isSealedSwiftCompatEnabled()) {
        return@forEach
      }
      if (Modifier.SEALED in type.modifiers) {
        sealedAdapterCodeGenerator.generate(
            targetType = type,
            isInternal = Modifier.INTERNAL in type.modifiers,
        )
      } else {
        subAdapterCodeGenerator.generate(
            targetType = type,
            isInternal = Modifier.INTERNAL in type.modifiers,
        )
      }
    }

    return emptyList()
  }
}
