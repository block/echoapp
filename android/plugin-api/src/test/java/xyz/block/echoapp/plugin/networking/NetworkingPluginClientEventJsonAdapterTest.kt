package xyz.block.echoapp.plugin.networking

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.networkingv2.internal.Error.FailedToParseProposedHumanReadableResponse
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginClientEvent.ErrorEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginClientEvent.FinalizedResponseEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginClientEvent.RequestEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginClientEventJsonAdapter
import xyz.block.echoapp.plugin.networkingv2.internal.Request
import xyz.block.echoapp.plugin.networkingv2.internal.Response
import org.junit.Test

class NetworkingPluginClientEventJsonAdapterTest {
  private val adapter = NetworkingPluginClientEventJsonAdapter(moshi = echoMoshi)

  @Test
  fun `fromJson for RequestEvent`() {
    val json =
        """
        {
          "request": {
            "_0": {
              "id": "req-1",
              "timestamp": 123456789,
              "httpMethod": "GET",
              "url": "https://example.com",
              "headers": {
                "Vary": "Accept-Encoding"
              },
              "humanReadableBody": "body",
              "rawBody": null
            },
            "proxy": true
          }
        }
        """
            .trimIndent()
    val event = adapter.fromJson(json)
    assertThat(event).isInstanceOf(RequestEvent::class.java)

    val requestEvent = event as RequestEvent
    assertThat(requestEvent.request.id).isEqualTo("req-1")
    assertThat(requestEvent.request.timestamp).isEqualTo(123456789L)
    assertThat(requestEvent.request.httpMethod).isEqualTo("GET")
    assertThat(requestEvent.request.url).isEqualTo("https://example.com")
    assertThat(requestEvent.request.headers).isEqualTo(mapOf("Vary" to "Accept-Encoding"))
    assertThat(requestEvent.request.humanReadableBody).isEqualTo("body")
    assertThat(requestEvent.request.rawBody).isEqualTo(null)
    assertThat(requestEvent.proxy).isEqualTo(true)
  }

  @Test
  fun `validate toJson for RequestEvent`() {
    val event =
        RequestEvent(
            request =
                Request(
                    id = "req-1",
                    timestamp = 123456789L,
                    httpMethod = "GET",
                    url = "https://example.com",
                    headers = mapOf("Accept" to "application/json"),
                    humanReadableBody = "body",
                    rawBody = null,
                ),
            proxy = true,
        )
    val json = adapter.toJson(event)
    val expectedJson =
        """
        {"request":{"_0":{"id":"req-1","timestamp":123456789,"httpMethod":"GET","url":"https://example.com","headers":{"Accept":"application/json"},"humanReadableBody":"body"},"proxy":true}}
        """
            .trimIndent()
            .replace("\n", "")
    assertThat(json.replace("\n", "")).isEqualTo(expectedJson)
  }

  @Test
  fun `validate fromJson for FinalizedResponseEvent`() {
    val json =
        """
        {
          "finalizedResponse": {
            "_0": {
              "requestID": "req-2",
              "statusCode": 200,
              "headers": {"Content-Type": "application/json"},
              "body": "{\"result\":\"ok\"}"
            }
          }
        }
        """
            .trimIndent()
    val event = adapter.fromJson(json)
    assertThat(event).isInstanceOf(FinalizedResponseEvent::class.java)

    val finalizedResponseEvent = event as FinalizedResponseEvent
    assertThat(finalizedResponseEvent.response.requestID).isEqualTo("req-2")
    assertThat(finalizedResponseEvent.response.statusCode).isEqualTo(200)
    assertThat(
            finalizedResponseEvent.response.headers,
        )
        .isEqualTo(mapOf("Content-Type" to "application/json"))
    assertThat(finalizedResponseEvent.response.body).isEqualTo("{\"result\":\"ok\"}")
  }

  @Test
  fun `validate toJson for FinalizedResponseEvent`() {
    val event =
        FinalizedResponseEvent(
            response =
                Response(
                    requestID = "req-2",
                    statusCode = 200,
                    headers = mapOf("Content-Type" to "application/json"),
                    body = "{\"result\":\"ok\"}",
                ),
        )
    val json = adapter.toJson(event)
    val expectedJson =
        """
        {"finalizedResponse":{"_0":{"requestID":"req-2","statusCode":200,"headers":{"Content-Type":"application/json"},"body":"{\"result\":\"ok\"}"}}}
        """
            .trimIndent()
            .replace("\n", "")
    assertThat(json.replace("\n", "")).isEqualTo(expectedJson)
  }

  @Test
  fun `validate fromJson for ErrorEvent`() {
    val json =
        """
        {
          "error": {
            "_0": {
              "failedToParseProposedHumanReadableResponse": {
                "reason": "bad format"
              }
            },
            "requestID": "req-3"
          }
        }
        """
            .trimIndent()
    val event = adapter.fromJson(json)
    assertThat(event).isInstanceOf(ErrorEvent::class.java)

    val errorEvent = event as ErrorEvent
    assertThat(errorEvent.requestID).isEqualTo("req-3")
    assertThat(errorEvent.error)
        .isEqualTo(
            FailedToParseProposedHumanReadableResponse(reason = "bad format"),
        )

    val errorType = errorEvent.error as FailedToParseProposedHumanReadableResponse
    assertThat(errorType.reason).isEqualTo("bad format")
  }

  @Test
  fun `validate toJson for ErrorEvent`() {
    val event =
        ErrorEvent(
            error = FailedToParseProposedHumanReadableResponse("bad format"),
            requestID = "req-3",
        )
    val json = adapter.toJson(event)
    val expectedJson =
        """
        {"error":{"_0":{"failedToParseProposedHumanReadableResponse":{"reason":"bad format"}},"requestID":"req-3"}}
        """
            .trimIndent()
            .replace("\n", "")
    assertThat(json.replace("\n", "")).isEqualTo(expectedJson)
  }
}
