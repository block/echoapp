package xyz.block.echoapp.plugin.networkingv2.internal

import xyz.block.echoapp.plugin.networkingv2.NetworkingPluginV2
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** Events sent by the server (Echo.app) when using **Proxy Mode** for [NetworkingPluginV2]. */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface NetworkingPluginServerEvent {
  /**
   * Echo.app provided a raw HTTP response (typically by proxying the original request). The client
   * should use the provided response, then send `.finalizedResponse` to complete the interaction.
   */
  @Json(name = "rawResponse")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class RawResponseEvent(
      val response: RawResponse,
  ) : NetworkingPluginServerEvent

  /**
   * Echo.app provided a human-readable response (typically a fixture). The client should parse the
   * response and use it, then send `.finalizedResponse` to complete the interaction.
   */
  @Json(name = "proposedHumanReadableResponse")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class ProposedHumanReadableResponseEvent(
      val response: HumanReadableResponse,
  ) : NetworkingPluginServerEvent
}
