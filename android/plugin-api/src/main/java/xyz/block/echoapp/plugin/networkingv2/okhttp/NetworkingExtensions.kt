package xyz.block.echoapp.plugin.networkingv2.okhttp

import xyz.block.echoapp.plugin.networking.okhttp.NetworkingBodyPrettyPrinter
import xyz.block.echoapp.plugin.networking.okhttp.NetworkingBodyPrettyPrinter.PrettyPrintResult
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.EOFException
import java.util.zip.GZIPInputStream
import kotlin.math.min
import kotlin.text.Charsets.UTF_8
import okhttp3.Headers
import okhttp3.Request
import okhttp3.Response
import okio.Buffer

internal object NetworkingExtensions {
  fun Request.prettyPrintedBody(
      bodyPrettyPrinters: Set<NetworkingBodyPrettyPrinter>,
      maxBodyByteCount: Long,
  ): PrettyPrintResult {
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

  fun Response.prettyPrintedBody(
      bodyPrettyPrinters: Set<NetworkingBodyPrettyPrinter>,
      maxBodyByteCount: Long,
  ): PrettyPrintResult {
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

  fun Headers.isGzipped(): Boolean {
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

  internal const val CONTENT_ENCODING_HEADER_NAME = "Content-Encoding"
}
