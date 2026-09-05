package xyz.block.echoapp.plugin.networking.okhttp

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.networking.internal.DeprecatedNetworkingEndpoint
import xyz.block.echoapp.plugin.networking.okhttp.EchoNetworkingInterceptor.Companion.CONTENT_ENCODING_HEADER_NAME
import xyz.block.echoapp.plugin.networking.okhttp.EchoNetworkingInterceptor.Companion.DEFAULT_MAX_BODY_BYTES_COUNT
import xyz.block.echoapp.plugin.networking.okhttp.NetworkingBodyPrettyPrinter.PrettyPrintResult
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.nio.charset.StandardCharsets.UTF_8
import java.util.zip.GZIPOutputStream
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.internal.closeQuietly
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.After
import org.junit.Before
import org.junit.Test

class EchoNetworkingInterceptorTest {
  private val mockwebserver = MockWebServer()
  private val fakeNetworkingPlugin =
      FakeNetworkingPlugin(
          currentTimeMillisProvider = { FAKE_CURRENT_TIME_MILLIS },
      )

  @Before
  fun setUp() {
    mockwebserver.start(
        InetAddress.getLocalHost(),
        port = TEST_SERVER_PORT,
    )
  }

  @After
  fun tearDown() {
    mockwebserver.shutdown()
  }

  @Test
  fun `logs requests and responses to the plugin`() = runTest {
    mockwebserver.enqueue(
        MockResponse()
            .setHeader("X-Test-Response-Header", "Hi there")
            .setBody("Fake response body"),
    )

    backgroundScope.launch {
      val call =
          createOkHttpClient()
              .newCall(
                  Request.Builder()
                      .url(
                          "http://${mockwebserver.hostName}:${TEST_SERVER_PORT}/fake-path?testParam=hey")
                      .header("X-Test-Request-Header", "Hello, world!")
                      .post("Fake request body".toRequestBody("text/plain".toMediaType()))
                      .build(),
              )
      call.await()
    }

    with(fakeNetworkingPlugin.awaitLogRequest().request) {
      assertThat(id).isEqualTo(FAKE_REQUEST_ID)
      assertThat(timestamp).isEqualTo(FAKE_CURRENT_TIME_MILLIS)
      assertThat(httpMethod).isEqualTo("POST")
      assertThat(endpoint).isEqualTo(DeprecatedNetworkingEndpoint("/fake-path"))
      assertThat(queryParameters).isEqualTo(mapOf("testParam" to "hey"))
      assertThat(headers).containsEntry("X-Test-Request-Header", "Hello, world!")
      assertThat(headers).containsEntry("X-Echo-Networking-UUID", "fake-request-id")
      assertThat(humanReadableBody).isEqualTo("Fake request body")
    }

    with(fakeNetworkingPlugin.awaitLogResponse().response) {
      assertThat(requestID).isEqualTo(FAKE_REQUEST_ID)
      assertThat(statusCode).isEqualTo(200)
      assertThat(headers).containsEntry("X-Test-Response-Header", "Hi there")
      assertThat(humanReadableBody).isEqualTo("Fake response body")
    }

    backgroundScope.cancel()
  }

  @Test
  fun `unzips request and response bodies compressed with gzip`() = runTest {
    mockwebserver.enqueue(
        MockResponse()
            .setHeader(CONTENT_ENCODING_HEADER_NAME, "gzip")
            .setBody(Buffer().write("Compressed response body".gzip())),
    )

    backgroundScope.launch {
      val call =
          createOkHttpClient()
              .newCall(
                  Request.Builder()
                      .url("http://${mockwebserver.hostName}:${TEST_SERVER_PORT}")
                      .header(CONTENT_ENCODING_HEADER_NAME, "gzip")
                      .post(
                          "Compressed request body"
                              .gzip()
                              .toRequestBody("text/plain".toMediaType()))
                      .build(),
              )
      call.await()
    }

    val loggedRequest = fakeNetworkingPlugin.awaitLogRequest().request
    assertThat(loggedRequest.humanReadableBody).isEqualTo("Compressed request body")

    val loggedResponse = fakeNetworkingPlugin.awaitLogResponse().response
    assertThat(loggedResponse.humanReadableBody).isEqualTo("Compressed response body")

    backgroundScope.cancel()
  }

  @Test
  fun `pretty prints request and response bodies by media type`() = runTest {
    mockwebserver.enqueue(
        MockResponse()
            .setHeader(CONTENT_TYPE_HEADER_NAME, "text/plain")
            .setBody("lowercase response body"),
    )

    backgroundScope.launch {
      val call =
          createOkHttpClient(prettyPrinters = setOf(AllCapsTextPrettyPrinter))
              .newCall(
                  Request.Builder()
                      .url("http://${mockwebserver.hostName}:${TEST_SERVER_PORT}")
                      .header(CONTENT_TYPE_HEADER_NAME, "text/plain")
                      .post("lowercase request body".toRequestBody("text/plain".toMediaType()))
                      .build(),
              )
      call.await()
    }

    val loggedRequest = fakeNetworkingPlugin.awaitLogRequest().request
    assertThat(loggedRequest.humanReadableBody).isEqualTo("LOWERCASE REQUEST BODY")

    val loggedResponse = fakeNetworkingPlugin.awaitLogResponse().response
    assertThat(loggedResponse.humanReadableBody).isEqualTo("LOWERCASE RESPONSE BODY")

    backgroundScope.cancel()
  }

  @Test
  fun `limits logged request and response body byte count`() = runTest {
    mockwebserver.enqueue(
        MockResponse()
            .setHeader(CONTENT_TYPE_HEADER_NAME, "text/plain")
            .setBody("Hi again, this is a sentence in the response body."),
    )

    backgroundScope.launch {
      val call =
          createOkHttpClient(maxBodyByteCount = 4)
              .newCall(
                  Request.Builder()
                      .url("http://${mockwebserver.hostName}:${TEST_SERVER_PORT}")
                      .post(
                          "Hello world, this is a sentence in the request body."
                              .toRequestBody("text/plain".toMediaType()),
                      )
                      .build(),
              )
      call.await()
    }

    val loggedRequest = fakeNetworkingPlugin.awaitLogRequest().request
    assertThat(loggedRequest.humanReadableBody).isEqualTo("Hell")

    val loggedResponse = fakeNetworkingPlugin.awaitLogResponse().response
    assertThat(loggedResponse.humanReadableBody).isEqualTo("Hi a")

    backgroundScope.cancel()
  }

  private fun createOkHttpClient(
      maxBodyByteCount: Long = DEFAULT_MAX_BODY_BYTES_COUNT,
      prettyPrinters: Set<NetworkingBodyPrettyPrinter> = emptySet(),
  ): OkHttpClient {
    val interceptor =
        EchoNetworkingInterceptor(
            networkingPlugin = fakeNetworkingPlugin,
            uuidProvider = { FAKE_REQUEST_ID },
            bodyPrettyPrinters = prettyPrinters,
            maxBodyByteCount = maxBodyByteCount,
        )
    return OkHttpClient.Builder().addNetworkInterceptor(interceptor).build()
  }

  private fun String.gzip(): ByteArray {
    val output = ByteArrayOutputStream()
    val gzipOutput = GZIPOutputStream(output)
    val input = ByteArrayInputStream(toByteArray())
    try {
      input.copyTo(gzipOutput)
    } finally {
      input.closeQuietly()
      gzipOutput.closeQuietly()
      output.closeQuietly()
    }
    return output.toByteArray()
  }

  private object AllCapsTextPrettyPrinter : NetworkingBodyPrettyPrinter {
    override fun prettyPrint(
        request: Request,
        body: ByteArray,
    ): PrettyPrintResult = PrettyPrintResult(humanReadableBody = body.toString(UTF_8).uppercase())

    override fun prettyPrint(
        response: Response,
        body: ByteArray,
    ): PrettyPrintResult = PrettyPrintResult(humanReadableBody = body.toString(UTF_8).uppercase())
  }

  private companion object {
    const val CONTENT_TYPE_HEADER_NAME = "Content-Type"
    const val FAKE_CURRENT_TIME_MILLIS = 1_719_840_447_991L
    const val FAKE_REQUEST_ID = "fake-request-id"
    const val TEST_SERVER_PORT = 9999
  }
}
