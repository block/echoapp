package xyz.block.echoapp.plugin.keyvaluestore.internal.events

import xyz.block.echoapp.plugin.keyvaluestore.internal.stores.KeyValueStoreSnapshot
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** Events sent by the client to the desktop app for `KeyValueStorePlugin`. */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface KeyValueStoreClientEvent {
  @Json(name = "updateSnapshot")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class UpdateSnapshot(
      val snapshot: KeyValueStoreSnapshot,
  ) : KeyValueStoreClientEvent

  @Json(name = "error")
  @JsonClass(generateAdapter = true)
  data class Error(
      val storeId: String,
      val message: String,
  ) : KeyValueStoreClientEvent

  @Json(name = "changeConfirmation")
  @JsonClass(generateAdapter = true)
  data class ChangeConfirmation(
      val changeId: String,
      @Json(name = "timestamp") val timestampMillis: Long,
      val success: Boolean,
  ) : KeyValueStoreClientEvent

  @Json(name = "changeConflict")
  @JsonClass(generateAdapter = true)
  data class ChangeConflict(
      val changeId: String,
      val key: String,
      val appValue: KeyValue,
      val desktopValue: KeyValue,
      @Json(name = "appTimestamp") val appTimestampMillis: Long,
      @Json(name = "desktopTimestamp") val desktopTimestampMillis: Long,
  ) : KeyValueStoreClientEvent
}
