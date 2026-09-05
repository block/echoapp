# ProGuard rules for Echo Plugin API - Consumer Rules

# These rules are automatically applied to projects that depend on this library

# Keep all generated JSON adapters from sealed-swift-compat and regular Moshi
-keep class * extends com.squareup.moshi.JsonAdapter { *; }

# Keep classes annotated with @JsonClass
-keep @com.squareup.moshi.JsonClass class * { *; }
