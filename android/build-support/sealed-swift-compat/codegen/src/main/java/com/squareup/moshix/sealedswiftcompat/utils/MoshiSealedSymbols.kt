package com.squareup.moshix.sealedswiftcompat.utils

import com.google.devtools.ksp.processing.Resolver
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import com.squareup.moshi.Moshi

/**
 * Based on
 * [https://github.com/ZacSweers/MoshiX/blob/main/moshi-sealed/codegen/src/main/kotlin/dev/zacsweers/moshix/sealed/codegen/ksp/MoshiSealedSymbols.kt].
 */
internal class MoshiSealedSymbols(resolver: Resolver) {
  val json = resolver.getClassDeclarationByName<Json>().asType()
  val jsonClass = resolver.getClassDeclarationByName<JsonClass>().asType()
  val moshi = resolver.getClassDeclarationByName<Moshi>().asType()
}
