package xyz.block.echoapp.plugin.keyvaluestore.internal.events

import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** Events sent to the client from the desktop app for `KeyValueStorePlugin`. */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface KeyValueStoreDesktopEvent {
  @Json(name = "requestSnapshot") data object RequestSnapshot : KeyValueStoreDesktopEvent

  @Json(name = "updateValue")
  @JsonClass(generateAdapter = true)
  data class UpdateValue(
      val changeId: String,
      val storeId: String,
      val key: String,
      val newValue: KeyValue,
      val type: KeyValueType,
      @Json(name = "timestamp") val timestampMillis: Long,
  ) : KeyValueStoreDesktopEvent

  @Json(name = "addKey")
  @JsonClass(generateAdapter = true)
  data class AddKey(
      val changeId: String,
      val storeId: String,
      val key: String,
      val value: KeyValue,
      val type: KeyValueType,
      @Json(name = "timestamp") val timestampMillis: Long,
  ) : KeyValueStoreDesktopEvent

  @Json(name = "deleteKey")
  @JsonClass(generateAdapter = true)
  data class DeleteKey(
      val changeId: String,
      val storeId: String,
      val key: String,
      @Json(name = "timestamp") val timestampMillis: Long,
  ) : KeyValueStoreDesktopEvent

  @Json(name = "requestFullRefresh") data object RequestFullRefresh : KeyValueStoreDesktopEvent
}
