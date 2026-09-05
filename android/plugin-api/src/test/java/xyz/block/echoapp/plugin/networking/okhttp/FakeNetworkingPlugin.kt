package xyz.block.echoapp.plugin.networking.okhttp

import com.google.common.truth.Truth.assertWithMessage
import xyz.block.echoapp.plugin.networking.NetworkingPlugin
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEndpoint
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingRequest
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingRequest.RequestData
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingResponse
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEvent.DeprecatedNetworkingResponse.ResponseData
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first

/** An implementation of [NetworkingPlugin] for unit testing [EchoNetworkingInterceptor]. */
internal class FakeNetworkingPlugin(
    private val currentTimeMillisProvider: () -> Long,
) :
    NetworkingPlugin(
        currentTimeMillisProvider = currentTimeMillisProvider,
    ) {
  private val onLogRequest = MutableSharedFlow<DeprecatedNetworkingRequest>(extraBufferCapacity = 1)
  private val onLogResponse =
      MutableSharedFlow<DeprecatedNetworkingResponse>(extraBufferCapacity = 1)

  suspend fun awaitLogRequest(): DeprecatedNetworkingRequest = onLogRequest.first()

  suspend fun awaitLogResponse(): DeprecatedNetworkingResponse = onLogResponse.first()

  override fun logRequest(
      id: String,
      httpMethod: String,
      path: String,
      queryParameters: Map<String, Any>,
      headers: Map<String, Any>,
      humanReadableBody: String,
  ) {
    super.logRequest(id, httpMethod, path, queryParameters, headers, humanReadableBody)
    val result =
        onLogRequest.tryEmit(
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
    assertWithMessage("Unable to emit request event").that(result).isTrue()
  }

  override fun logResponse(
      requestId: String,
      statusCode: Int,
      headers: Map<String, Any>,
      humanReadableBody: String,
  ) {
    super.logResponse(requestId, statusCode, headers, humanReadableBody)
    val result =
        onLogResponse.tryEmit(
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
    assertWithMessage("Unable to emit response event").that(result).isTrue()
  }
}
