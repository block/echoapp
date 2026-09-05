package xyz.block.echoapp.plugin.networking

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

@Deprecated("V1 NetworkingPlugin is deprecated.")
class NetworkingPluginTest {
  private val fakeCurrentTimestamp = 1_719_710_688_043

  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val plugin =
      NetworkingPlugin(
          currentTimeMillisProvider = { fakeCurrentTimestamp },
      )

  @Test
  fun `networking plugin has expected ID`() {
    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.network")
  }

  @Test
  fun `networking plugin logs request over the connection`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    val id = "request id"
    val httpMethod = "GET"
    val path = "/path"
    val queryParameterKey = "query param key"
    val queryParameterValue = "query param value"
    val headerKey = "header key"
    val headerValue = "header value"
    val humanReadableBody = "request body"
    plugin.logRequest(
        id = id,
        httpMethod = httpMethod,
        path = path,
        queryParameters = mapOf(queryParameterKey to queryParameterValue),
        headers = mapOf(headerKey to headerValue),
        humanReadableBody = humanReadableBody,
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"request\":{\"_0\":{" +
                "\"id\":\"$id\"," +
                "\"timestamp\":$fakeCurrentTimestamp," +
                "\"httpMethod\":\"$httpMethod\"," +
                "\"endpoint\":{\"path\":\"$path\"}," +
                "\"queryParameters\":{\"$queryParameterKey\":\"$queryParameterValue\"}," +
                "\"headers\":{\"$headerKey\":\"$headerValue\"}," +
                "\"humanReadableBody\":\"$humanReadableBody\"" +
                "}}}",
        )
  }

  @Test
  fun `networking plugin logs response over the connection`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    val requestId = "request id"
    val statusCode = 404
    val headerKey = "header key"
    val headerValue = "header value"
    val humanReadableBody = "response-body"
    plugin.logResponse(
        requestId = requestId,
        statusCode = statusCode,
        headers = mapOf(headerKey to headerValue),
        humanReadableBody = humanReadableBody,
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"response\":{\"_0\":{" +
                "\"requestID\":\"$requestId\"," +
                "\"statusCode\":$statusCode," +
                "\"headers\":{\"$headerKey\":\"$headerValue\"}," +
                "\"humanReadableBody\":\"$humanReadableBody\"" +
                "}}}",
        )
  }
}
