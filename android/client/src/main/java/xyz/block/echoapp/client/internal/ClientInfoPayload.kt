package xyz.block.echoapp.client.internal

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/**
 * Sent to the desktop client to configure enabled plugins. [pluginIds] should match all available
 * plugins known to the client.
 */
@JsonClass(generateAdapter = true)
internal data class ClientInfoPayload(
    @Json(name = "client_plugin_ids") val pluginIds: List<String>,
)
