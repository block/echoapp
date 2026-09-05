package xyz.block.echoapp.plugin.appinfo

@DslMarker @Target(AnnotationTarget.CLASS, AnnotationTarget.TYPE) annotation class AppInfoDsl

typealias KeyValueEntry = Pair<String, String>

/** Provides the DSL for [AppInfoPlugin.buildAppInfo]. */
@AppInfoDsl
class AppInfoBuilder {
  private val scopes = mutableMapOf<String, MutableSet<KeyValueEntry>>()

  /** Adds or updates a scope (section). */
  fun scope(
      name: String,
      builder: ScopeBuilder.() -> Unit,
  ) {
    ScopeBuilder(
            scopeEntries = scopes.getOrPut(name) { mutableSetOf() },
        )
        .builder()
  }

  internal fun toAppInfoEntries(): List<AppInfoEntry> {
    return scopes.flatMap { (scope, entries) ->
      entries.map { (key, value) -> AppInfoEntry(scope, key, value) }
    }
  }
}

/** Used by [AppInfoBuilder.scope]; adds entries to a scope (section). */
@AppInfoDsl
class ScopeBuilder(
    private val scopeEntries: MutableSet<KeyValueEntry>,
) {
  /** Appends an entry to the current scope (section). */
  fun entry(
      key: String,
      value: String,
  ) {
    scopeEntries.add(KeyValueEntry(key, value))
  }
}
