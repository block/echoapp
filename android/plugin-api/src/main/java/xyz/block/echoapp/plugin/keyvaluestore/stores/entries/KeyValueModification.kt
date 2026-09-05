package xyz.block.echoapp.plugin.keyvaluestore.stores.entries

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** Tracks changes to [KeyValueEntries][KeyValueEntry] over time. */
@JsonClass(generateAdapter = true)
data class KeyValueModification(
    @Json(name = "timestamp") val timestampMillis: Long,
    val oldValue: KeyValue?,
    val newValue: KeyValue,
    val source: ModificationSource,
    val changeDescription: String,
    val changeId: String?,
) {
  @Suppress("unused")
  enum class ModificationSource {
    @Json(name = "App") APP,
    @Json(name = "Echo Desktop") DESKTOP,
    @Json(name = "System") SYSTEM,
    @Json(name = "Unknown") UNKNOWN,
  }
}
