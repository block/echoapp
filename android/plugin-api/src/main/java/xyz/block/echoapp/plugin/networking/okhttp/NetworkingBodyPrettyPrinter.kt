package xyz.block.echoapp.plugin.networking.okhttp

import okhttp3.Request
import okhttp3.Response

/**
 * Enables apps that use [EchoNetworkingInterceptor] to easily implement custom logic for displaying
 * request and response bodies in a human-readable format.
 *
 * These are given as a set when instantiating [EchoNetworkingInterceptor].
 */
interface NetworkingBodyPrettyPrinter {
  /**
   * The result of pretty printing a request or response body.
   *
   * If [contentType] is not null, it will override the value of the `Content-Type` header sent to
   * Echo; this does not affect the headers in the real request or response. This is helpful for
   * giving Echo a hint on how to format or highlight the value, when applicable.
   */
  data class PrettyPrintResult(
      val humanReadableBody: String,
      val contentType: String? = null,
  )

  /** Pretty prints the given [request]'s [body]. Returns null if it can't be handled. */
  fun prettyPrint(
      request: Request,
      body: ByteArray,
  ): PrettyPrintResult?

  /** Pretty prints the given [response]'s [body]. Returns null if it can't be handled. */
  fun prettyPrint(
      response: Response,
      body: ByteArray,
  ): PrettyPrintResult?
}
