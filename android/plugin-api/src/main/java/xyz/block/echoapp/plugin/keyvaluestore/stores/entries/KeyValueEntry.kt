package xyz.block.echoapp.plugin.keyvaluestore.stores.entries

import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** A single key-value entry in a [KeyValueStore]. */
@JsonClass(generateAdapter = true)
data class KeyValueEntry(
    val key: String,
    val value: KeyValue,
    val isEditable: Boolean,
    @Json(name = "lastModified") val lastModifiedMillis: Long? = null,
    val modificationHistory: List<KeyValueModification> = emptyList(),
    val type: KeyValueType = value.type,
)
