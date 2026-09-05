package xyz.block.echoapp.plugin.networkingv2.internal

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Response<T>(
    val requestID: String,
    val statusCode: Int,
    val headers: Map<String, String>,
    val body: T?,
)

typealias HumanReadableResponse = Response<String>

typealias RawResponse = Response<ByteArray>
