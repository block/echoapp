package xyz.block.echoapp.plugin.networking

import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.buffered.BufferedClientPlugin
import xyz.block.echoapp.plugin.buffered.DEFAULT_BUFFER_SIZE
import xyz.block.echoapp.plugin.buffered.trySend
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEndpoint
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingRequest
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingRequest.RequestData
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingResponse
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingResponse.ResponseData
import xyz.block.echoapp.plugin.networking.okhttp.EchoNetworkingInterceptor

/**
 * A [ClientPlugin] that reports requests & responses for network calls. This plugin can be
 * instantiated…
 *
 * val networkingPlugin = NetworkingPlugin() networkingPlugin.logRequest(…)
 * networkingPlugin.logResponse(…)
 *
 * …or it can be overridden with a subclass. The most common way to use this plugin will likely be
 * through an interceptor, i.e. [EchoNetworkingInterceptor] for `OkHttpClient`.
 */
@OptIn(ExperimentalStdlibApi::class)
@Deprecated("Use the NetworkingPluginV2 instead.")
open class NetworkingPlugin(
    bufferSize: Int = DEFAULT_BUFFER_SIZE,
    private val currentTimeMillisProvider: () -> Long = { System.currentTimeMillis() },
) : BufferedClientPlugin(bufferSize = bufferSize) {
  override val pluginIdentifier = "com.echo.plugin.network"

  /**
   * Notifies the desktop app of a new outbound request. Should be followed by [logResponse].
   *
   * [id]: A unique ID for the request. [httpMethod]: The method, like "GET" or "POST". [path]: The
   * path of the requested URL, like "/some-endpoint". [queryParameters]: The query parameters of
   * the URL as a map. These are the URL's key/value pairs. [headers]: HTTP headers from the
   * request. [humanReadableBody]: A readable string of the request body to display in Echo.
   */
  open fun logRequest(
      id: String,
      httpMethod: String,
      path: String,
      queryParameters: Map<String, Any>,
      headers: Map<String, Any>,
      humanReadableBody: String,
  ) {
    trySend<DeprecatedNetworkingEvent>(
        model =
            DeprecatedNetworkingRequest(
                request =
                    RequestData(
                        id = id,
                        timestamp = currentTimeMillisProvider(),
                        httpMethod = httpMethod,
                        endpoint = DeprecatedNetworkingEndpoint(path),
                        queryParameters = queryParameters,
                        headers = headers,
                        humanReadableBody = humanReadableBody,
                    ),
            ),
    )
  }

  /**
   * Notifies the desktop app of a response to a previously logged request.
   *
   * [requestId]: A unique ID for the request, matching an ID given to [logRequest]. [statusCode]:
   * The HTTP status code from the response, i.e. 200 for "OK". [headers]: HTTP headers from the
   * response. [humanReadableBody]: A readable string of the response body to display in Echo.
   */
  open fun logResponse(
      requestId: String,
      statusCode: Int,
      headers: Map<String, Any>,
      humanReadableBody: String,
  ) {
    trySend<DeprecatedNetworkingEvent>(
        model =
            DeprecatedNetworkingResponse(
                response =
                    ResponseData(
                        requestID = requestId,
                        statusCode = statusCode,
                        headers = headers,
                        humanReadableBody = humanReadableBody,
                    ),
            ),
    )
  }
}
