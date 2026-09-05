package xyz.block.echoapp.plugin.networkingv2.internal

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Request(
    val id: String,
    val timestamp: Long,
    val httpMethod: String,
    val url: String,
    val headers: Map<String, String>,
    val humanReadableBody: String,
    val rawBody: ByteArray? = null,
)
