package xyz.block.echoapp.client.internal

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
internal data class PluginPayload(
    @Json(name = "plugin_id") val pluginId: String,
    val data: String,
)
