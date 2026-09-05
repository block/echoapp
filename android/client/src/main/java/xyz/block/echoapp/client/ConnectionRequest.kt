package xyz.block.echoapp.client

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class ConnectionRequest(
    @Json(name = "server_url") val serverUrl: String,
)
