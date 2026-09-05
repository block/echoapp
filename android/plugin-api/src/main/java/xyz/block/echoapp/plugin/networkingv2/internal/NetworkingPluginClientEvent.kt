package xyz.block.echoapp.plugin.networkingv2.internal

import xyz.block.echoapp.plugin.networkingv2.NetworkingPluginV2
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** Events sent by the client for [NetworkingPluginV2]. */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface NetworkingPluginClientEvent {
  /**
   * The client made a request.
   * - If `proxy` is `true`, Echo will **execute the request on behalf of** the client:
   *     1. The client **pauses execution** until Echo sends a response
   *        (`NetworkingPluginServerEvent`).
   *     2. The client processes the response and sends `.finalizedResponse` to complete the
   *        interaction.
   * - If `proxy` is `false`:
   *     1. The client **executes the request independently** using `URLSession` (or another
   *        networking API).
   *     2. The client **still sends** `.request(proxy: false)` to **notify Echo** that a request is
   *        being made.
   *     3. The client receives and processes the HTTP response **directly from the Web server**.
   *     4. The client sends `.finalizedResponse` to Echo to signal that the request is complete.
   *
   * In both cases, the client must **always** send `.finalizedResponse` when done.
   */
  @Json(name = "request")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class RequestEvent(
      val request: Request,
      @Json(name = "proxy") val proxy: Boolean,
  ) : NetworkingPluginClientEvent

  /**
   * The client should **always** send this when completing a network request, regardless of whether
   * or not the request was proxied. This response should be human readable (i.e. binary messages
   * should be converted to JSON or another human-readable format).
   */
  @Json(name = "finalizedResponse")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class FinalizedResponseEvent(
      val response: HumanReadableResponse,
  ) : NetworkingPluginClientEvent

  /** The client encountered an error. See [Error] enum for possible reasons. */
  @Json(name = "error")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class ErrorEvent(
      val error: Error,
      @Json(name = "requestID") val requestID: String,
  ) : NetworkingPluginClientEvent
}

/** Well-known errors emitted by the client plugin */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
sealed interface Error {
  /**
   * Echo.app sent a human-readable response (i.e. a fixture) to the client, but the client failed
   * to convert it to the expected format (e.g. a protobuf). Echo.app will display the error and
   * allow the user to provide a different response.
   */
  @Json(name = "failedToParseProposedHumanReadableResponse")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class FailedToParseProposedHumanReadableResponse(
      @Json(name = "reason") val reason: String,
  ) : Error
}
