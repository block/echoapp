package xyz.block.echoapp.plugin.networking.okhttp

import xyz.block.echoapp.plugin.networking.NetworkingPlugin
import xyz.block.echoapp.plugin.networking.okhttp.NetworkingBodyPrettyPrinter.PrettyPrintResult
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.EOFException
import java.util.UUID
import java.util.zip.GZIPInputStream
import kotlin.math.min
import kotlin.text.Charsets.UTF_8
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Interceptor.Chain
import okhttp3.Request
import okhttp3.Response
import okio.Buffer

/**
 * An OkHttp interceptor that logs request and response data to the [NetworkingPlugin], and assigns
 * the [REQUEST_UUID_HEADER_KEY] header to outbound requests.
 * - [networkingPlugin]: The [NetworkingPlugin] used to log requests and responses to the desktop
 *   app.
 * - [uuidProvider]: A lambda that generates unique IDs when invoked. Defaults to [UUID.randomUUID].
 * - [bodyPrettyPrinters]: Optional [NetworkingBodyPrettyPrinter]s that can process and change how
 *   the desktop app displays request and response bodies.
 * - [maxBodyByteCount]: The maximum number of bytes that will be pretty printed and sent to the
 *   desktop app. This helps prevent OutOfMemory exceptions.
 */
@Deprecated("Use EchoOkHttpInterceptorV2 instead")
open class EchoNetworkingInterceptor(
    private val networkingPlugin: NetworkingPlugin,
    private val uuidProvider: () -> String = { UUID.randomUUID().toString() },
    private val bodyPrettyPrinters: Set<NetworkingBodyPrettyPrinter> = emptySet(),
    private val maxBodyByteCount: Long = DEFAULT_MAX_BODY_BYTES_COUNT,
) : Interceptor {
  override fun intercept(chain: Chain): Response {
    val requestId = uuidProvider()
    val request = chain.request().newBuilder().header(REQUEST_UUID_HEADER_KEY, requestId).build()

    // Pretty printers can modify the Content-Type header sent to Echo.
    var requestHeaders = request.headers.toMap()
    val requestPrettyPrinted = request.prettyPrintedBody()
    requestPrettyPrinted.contentType?.let { contentType ->
      requestHeaders = requestHeaders + (CONTENT_TYPE_HEADER_NAME to contentType)
    }
    networkingPlugin.logRequest(
        id = requestId,
        httpMethod = request.method,
        path = request.url.encodedPath,
        queryParameters = request.url.queryParameters,
        headers = requestHeaders,
        humanReadableBody = requestPrettyPrinted.humanReadableBody,
    )

    return chain.proceed(request).also { response ->
      // Pretty printers can modify the Content-Type header sent to Echo.
      var responseHeaders = response.headers.toMap()
      val responsePrettyPrinted = response.prettyPrintedBody()
      responsePrettyPrinted.contentType?.let { contentType ->
        responseHeaders = responseHeaders + (CONTENT_TYPE_HEADER_NAME to contentType)
      }
      networkingPlugin.logResponse(
          requestId = requestId,
          statusCode = response.code,
          headers = responseHeaders,
          humanReadableBody = responsePrettyPrinted.humanReadableBody,
      )
    }
  }

  private val HttpUrl.queryParameters: Map<String, String>
    get() =
        queryParameterNames.associateWith { queryParameterValues(it).joinToString(separator = ",") }

  private fun Request.prettyPrintedBody(): PrettyPrintResult {
    val bodyBytes =
        try {
          body?.let { body ->
            val buffer = Buffer().also { body.writeTo(it) }
            val byteArray = buffer.readByteArray(min(buffer.size, maxBodyByteCount))
            unzipped(byteArray)
          } ?: ByteArray(0)
        } catch (e: Exception) {
          return PrettyPrintResult(
              humanReadableBody =
                  "Unable to unzip & process request body.\n" + e.stackTraceToString(),
          )
        }

    return bodyPrettyPrinters.firstNotNullOfOrNull { it.prettyPrint(this, bodyBytes) }
        ?: PrettyPrintResult(humanReadableBody = bodyBytes.toString(UTF_8))
  }

  private fun Response.prettyPrintedBody(): PrettyPrintResult {
    val bodyBytes =
        try {
          body
              ?.source()
              ?.also { it.request(maxBodyByteCount) }
              ?.buffer
              ?.clone()
              ?.use { it.readByteArray(min(it.size, maxBodyByteCount)) }
              ?.let { unzipped(it) } ?: ByteArray(0)
        } catch (e: Exception) {
          return PrettyPrintResult(
              humanReadableBody =
                  "Unable to unzip & process response body.\n" + e.stackTraceToString(),
          )
        }

    return bodyPrettyPrinters.firstNotNullOfOrNull { it.prettyPrint(this, bodyBytes) }
        ?: PrettyPrintResult(humanReadableBody = bodyBytes.toString(UTF_8))
  }

  @Throws(EOFException::class)
  private fun Request.unzipped(bodyBytes: ByteArray): ByteArray {
    return if (isGzipped()) bodyBytes.gunzip() else bodyBytes
  }

  @Throws(EOFException::class)
  private fun Response.unzipped(bodyBytes: ByteArray): ByteArray {
    return if (isGzipped()) bodyBytes.gunzip() else bodyBytes
  }

  private fun Request.isGzipped(): Boolean = headers.isGzipped()

  private fun Response.isGzipped(): Boolean = headers.isGzipped()

  private fun Headers.isGzipped(): Boolean {
    val encoding = firstOrNull { it.first.equals(CONTENT_ENCODING_HEADER_NAME, ignoreCase = true) }
    return encoding?.second.equals("gzip", ignoreCase = true)
  }

  @Throws(EOFException::class)
  private fun ByteArray.gunzip(): ByteArray {
    val output = ByteArrayOutputStream()
    val input = ByteArrayInputStream(this)
    val gzipInputStream = GZIPInputStream(input)
    try {
      gzipInputStream.copyTo(output)
    } finally {
      gzipInputStream.closeQuietly()
      input.closeQuietly()
      output.closeQuietly()
    }
    return output.toByteArray()
  }

  private fun Closeable.closeQuietly() {
    try {
      close()
    } catch (_: Exception) {}
  }

  companion object {
    const val DEFAULT_MAX_BODY_BYTES_COUNT = 200 * 1_024L
    internal const val CONTENT_ENCODING_HEADER_NAME = "Content-Encoding"
    internal const val CONTENT_TYPE_HEADER_NAME = "Content-Type"
    private const val REQUEST_UUID_HEADER_KEY = "X-Echo-Networking-UUID"
  }
}
