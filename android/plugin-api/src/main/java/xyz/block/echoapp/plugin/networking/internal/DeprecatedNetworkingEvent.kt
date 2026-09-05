package xyz.block.echoapp.plugin.networking.internal

import xyz.block.echoapp.plugin.networking.NetworkingPlugin
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** Used internally by [NetworkingPlugin] for serialization and deserialization. */
@Deprecated("V1 NetworkingPlugin is deprecated.")
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface DeprecatedNetworkingEvent {
  /** Represents an outbound network request, with a unique [RequestData.id]. */
  @Json(name = "request")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class DeprecatedNetworkingRequest(
      val request: RequestData,
  ) : DeprecatedNetworkingEvent {
    @JsonClass(generateAdapter = true)
    data class RequestData(
        val id: String,
        val timestamp: Long,
        val httpMethod: String,
        val endpoint: DeprecatedNetworkingEndpoint,
        val queryParameters: Map<String, Any>,
        val headers: Map<String, Any>,
        val humanReadableBody: String,
    )
  }

  /**
   * Represents a response to a [DeprecatedNetworkingRequest], with a [ResponseData.requestID] that
   * matches a previous [DeprecatedNetworkingRequest].
   */
  @Json(name = "response")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class DeprecatedNetworkingResponse(
      val response: ResponseData,
  ) : DeprecatedNetworkingEvent {
    @JsonClass(generateAdapter = true)
    data class ResponseData(
        val requestID: String,
        val statusCode: Int,
        val headers: Map<String, Any>,
        val humanReadableBody: String,
    )
  }
}

@JsonClass(generateAdapter = true)
internal data class DeprecatedNetworkingEndpoint(
    val path: String,
)
