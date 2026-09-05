package xyz.block.echoapp.plugin.keyvaluestore.internal.stores

import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** A snapshot of all stores at a given point in time. */
@JsonClass(generateAdapter = true)
internal data class KeyValueStoreSnapshot(
    val stores: List<KeyValueStore>,
    @Json(name = "timestamp") val timestampMillis: Long,
)
