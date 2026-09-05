package xyz.block.echoapp.plugin.networking.okhttp

import okhttp3.Request

/**
 * Used by [EchoNetworkingInterceptorV2] to convert proxied responses from the desktop app into
 * formats understood by the client app's networking stack.
 */
interface NetworkBodyConverter {
  fun parseHumanReadableResponseBody(
      humanReadableBody: String,
      request: Request,
  ): ByteArray
}
