package xyz.block.echoapp.plugin.networkingv2.okhttp

import xyz.block.echoapp.plugin.networking.okhttp.NetworkBodyConverter
import xyz.block.echoapp.plugin.networking.okhttp.NetworkingBodyPrettyPrinter
import xyz.block.echoapp.plugin.networkingv2.NetworkingPluginV2
import xyz.block.echoapp.plugin.networkingv2.internal.Error.FailedToParseProposedHumanReadableResponse
import xyz.block.echoapp.plugin.networkingv2.internal.HumanReadableResponse
import xyz.block.echoapp.plugin.networkingv2.internal.Request
import xyz.block.echoapp.plugin.networkingv2.internal.Response as EchoResponse
import xyz.block.echoapp.plugin.networkingv2.okhttp.NetworkingExtensions.isGzipped
import xyz.block.echoapp.plugin.networkingv2.okhttp.NetworkingExtensions.prettyPrintedBody
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.UUID
import java.util.zip.GZIPOutputStream
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.Headers
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Protocol
import okhttp3.Request as OkHttpRequest
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer

/**
 * OkHttp app interceptor that records network activity and supports proxying requests through
 * [NetworkingPluginV2].
 *
 * The proxying behavior is optional and can be enabled via [shouldProxyRequest].
 *
 * When proxying mode is enabled, if there is no connection to Echo, the interceptor will execute
 * the original request and simply record the activity with Echo.
 */
open class EchoNetworkingInterceptorV2(
    private val networkingPlugin: NetworkingPluginV2,
    private val uuidProvider: () -> String = { UUID.randomUUID().toString() },
    private val bodyPrettyPrinters: Set<NetworkingBodyPrettyPrinter> = emptySet(),
    private val bodyConverter: NetworkBodyConverter,
    private val maxBodyByteCount: Long = DEFAULT_MAX_BODY_BYTES_COUNT,
    private val currentTimeMillisProvider: () -> Long = { System.currentTimeMillis() },
    private val coroutineContext: CoroutineContext = Dispatchers.IO,
    /**
     * TODO: This is a temporary hack to allow consumers to use this as a network interceptor.
     *   However, this means the original network call will still be made in addition to Echo
     *   proxying the request. This is likely not what we want and should be removed.
     */
    private val isNetworkInterceptor: Boolean = false,
) : Interceptor {
  /** Controls whether this interceptor will proxy the request through [NetworkingPluginV2]. */
  open fun shouldProxyRequest(): Boolean = true

  override fun intercept(chain: Interceptor.Chain): Response {
    return runBlocking(coroutineContext) { proxyRequest(chain) }
  }

  private suspend fun proxyRequest(chain: Interceptor.Chain): Response {
    val requestId = uuidProvider()
    val request = chain.request().newBuilder().header(REQUEST_UUID_HEADER_KEY, requestId).build()

    // Convert OkHttp request to Echo request format
    val echoRequest = convertToEchoRequest(request, requestId)

    val shouldProxyRequest = shouldProxyRequest()
    if (!shouldProxyRequest || !networkingPlugin.isPluginConnected) {
      // If proxy mode is enabled, log a message so we know it's not proxying as expected.
      if (shouldProxyRequest) {
        EchoDebugLogger.error(TAG, "no connection to Echo, not proxying request to ${request.url}")
      }
      return executeOriginalRequest(chain, request, echoRequest)
    } else {
      EchoDebugLogger.debug(TAG, "Proxying request to ${request.url} with id=$requestId")

      if (isNetworkInterceptor) {
        chain.proceed(request)
      }

      return proxyRequest(echoRequest, request)
    }
  }

  private fun executeOriginalRequest(
      chain: Interceptor.Chain,
      request: OkHttpRequest,
      echoRequest: Request,
  ): Response {
    val originalResponse = chain.proceed(request)

    // Still record in passive mode for debugging
    networkingPlugin.recordRequest(echoRequest)
    val finalizedResponse = convertOkHttpResponseToEcho(originalResponse, echoRequest.id)
    networkingPlugin.finalizeResponse(finalizedResponse)

    return originalResponse
  }

  private suspend fun proxyRequest(
      echoRequest: Request,
      originalRequest: OkHttpRequest,
      isRetry: Boolean = false,
  ): Response {
    return try {
      val echoResponse =
          if (!isRetry) {
            networkingPlugin.proxy(echoRequest)
          } else {
            networkingPlugin.waitForResponse(echoRequest.id)
          }
      val okHttpResponse = convertToOkHttpResponse(echoResponse, originalRequest)
      val finalizedResponse = finalizeResponse(echoResponse, echoRequest, okHttpResponse)
      networkingPlugin.finalizeResponse(finalizedResponse)
      okHttpResponse
    } catch (e: FailedToParseHumanReadableResponseBodyException) {
      networkingPlugin.reportError(
          error =
              FailedToParseProposedHumanReadableResponse(
                  reason = "${e.message}\n${e.cause?.message.orEmpty()}",
              ),
          requestID = echoRequest.id,
      )
      proxyRequest(echoRequest, originalRequest, isRetry = true)
    } catch (e: Exception) {
      // Rethrow all other exceptions as an IOException so it surfaces as a network error
      throw IOException("Unexpected Echo network interceptor error", e).also {
        EchoDebugLogger.error(TAG, it.message.orEmpty(), it)
      }
    }
  }

  private fun convertToEchoRequest(
      request: OkHttpRequest,
      requestId: String,
  ): Request {
    val requestPrettyPrinted = request.prettyPrintedBody(bodyPrettyPrinters, maxBodyByteCount)

    val bodyBytes =
        request.body?.let { body ->
          val buffer = Buffer()
          body.writeTo(buffer)
          buffer.readByteArray()
        }

    // Make sure the content-type is included in the headers.
    val requestHeaders = request.headers.toMap().toMutableMap()
    val contentType = request.body?.contentType()
    if (!requestHeaders.containsKey(CONTENT_TYPE_HEADER_NAME) && contentType != null) {
      requestHeaders += (CONTENT_TYPE_HEADER_NAME to contentType.toString())
    }

    return Request(
        id = requestId,
        url = request.url.toString(),
        httpMethod = request.method,
        headers = requestHeaders,
        timestamp = currentTimeMillisProvider.invoke(),
        humanReadableBody = requestPrettyPrinted.humanReadableBody,
        rawBody = bodyBytes,
    )
  }

  private fun finalizeResponse(
      response: EchoResponse<*>,
      echoRequest: Request,
      okHttpResponse: Response,
  ): HumanReadableResponse {
    // Convert the response body to human-readable format based on body type
    val humanReadableBody =
        when (val body = response.body) {
          is ByteArray -> prettyPrintResponseBody(body, okHttpResponse).humanReadableBody
          is String -> body
          null -> ""
          else -> body.toString()
        }

    return HumanReadableResponse(
        requestID = echoRequest.id,
        headers = response.headers,
        body = humanReadableBody,
        statusCode = response.statusCode,
    )
  }

  private fun convertToOkHttpResponse(
      echoResponse: EchoResponse<*>,
      originalRequest: OkHttpRequest,
  ): Response {
    val headers =
        Headers.Builder()
            .apply { echoResponse.headers.forEach { (name, value) -> add(name, value) } }
            .build()

    val contentType = headers[CONTENT_TYPE_HEADER_NAME]?.toMediaType()
    val responseBody =
        when (val body = echoResponse.body) {
          is ByteArray -> {
            if (headers.isGzipped()) {
                  gzipByteArray(body)
                } else {
                  body
                }
                .toResponseBody(contentType)
          }
          is String ->
              try {
                bodyConverter
                    .parseHumanReadableResponseBody(body, originalRequest)
                    .toResponseBody(contentType)
              } catch (e: Exception) {
                throw FailedToParseHumanReadableResponseBodyException(e).also {
                  EchoDebugLogger.error(TAG, it.message.orEmpty(), it)
                }
              }
          null -> ByteArray(0).toResponseBody("application/octet-stream".toMediaType())
          else -> body.toString().toResponseBody("text/plain".toMediaType())
        }

    return Response.Builder()
        .request(originalRequest)
        .protocol(Protocol.HTTP_2)
        .code(echoResponse.statusCode)
        .message(getStatusMessage(echoResponse.statusCode))
        .headers(headers)
        .body(responseBody)
        .build()
  }

  private fun gzipByteArray(data: ByteArray) =
      ByteArrayOutputStream().use { output ->
        GZIPOutputStream(output).use { it.write(data) }
        output.toByteArray()
      }

  private fun convertOkHttpResponseToEcho(
      response: Response,
      requestId: String,
  ): HumanReadableResponse {
    val prettyPrinted = response.prettyPrintedBody(bodyPrettyPrinters, maxBodyByteCount)

    return HumanReadableResponse(
        requestID = requestId,
        headers = response.headers.toMap(),
        body = prettyPrinted.humanReadableBody,
        statusCode = response.code,
    )
  }

  private fun prettyPrintResponseBody(
      bodyBytes: ByteArray?,
      okHttpResponse: Response,
  ): NetworkingBodyPrettyPrinter.PrettyPrintResult {
    if (bodyBytes == null || bodyBytes.isEmpty()) {
      return NetworkingBodyPrettyPrinter.PrettyPrintResult(
          humanReadableBody = "",
      )
    }

    // Try each pretty printer
    for (printer in bodyPrettyPrinters) {
      val result = printer.prettyPrint(okHttpResponse, bodyBytes)
      if (result != null) {
        return result
      }
    }

    // Default: try to convert to string if possible
    return try {
      val bodyString = bodyBytes.toString(Charsets.UTF_8)
      val truncated = bodyBytes.size > maxBodyByteCount
      val displayBody =
          if (truncated) {
            bodyString.take(maxBodyByteCount.toInt()) + "...[truncated]"
          } else {
            bodyString
          }
      NetworkingBodyPrettyPrinter.PrettyPrintResult(
          humanReadableBody = displayBody,
      )
    } catch (e: Exception) {
      NetworkingBodyPrettyPrinter.PrettyPrintResult(
          humanReadableBody = "[Binary data: ${bodyBytes.size} bytes]",
      )
    }
  }

  private fun getStatusMessage(code: Int): String =
      when (code) {
        200 -> "OK"
        201 -> "Created"
        204 -> "No Content"
        400 -> "Bad Request"
        401 -> "Unauthorized"
        403 -> "Forbidden"
        404 -> "Not Found"
        405 -> "Method Not Allowed"
        409 -> "Conflict"
        500 -> "Internal Server Error"
        502 -> "Bad Gateway"
        503 -> "Service Unavailable"
        else -> "Unknown"
      }

  private class FailedToParseHumanReadableResponseBodyException(exception: Exception) :
      Exception(
          "Failed to parse human readable response body",
          exception,
      )

  companion object {
    const val DEFAULT_MAX_BODY_BYTES_COUNT = 200 * 1_024L
    internal const val CONTENT_TYPE_HEADER_NAME = "Content-Type"
    private const val REQUEST_UUID_HEADER_KEY = "X-Echo-Networking-UUID"
    private val TAG = EchoNetworkingInterceptorV2::class.simpleName!!
  }
}
