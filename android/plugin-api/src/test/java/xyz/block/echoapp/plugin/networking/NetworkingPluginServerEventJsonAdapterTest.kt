package xyz.block.echoapp.plugin.networking

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginServerEvent.ProposedHumanReadableResponseEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginServerEvent.RawResponseEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginServerEventJsonAdapter
import xyz.block.echoapp.plugin.networkingv2.internal.Response
import org.junit.Test

class NetworkingPluginServerEventJsonAdapterTest {
  private val adapter = NetworkingPluginServerEventJsonAdapter(moshi = echoMoshi)

  @Test
  fun `validate rawResponse fromJson`() {
    val event =
        adapter.fromJson(
            """
            {
              "rawResponse": {
                "_0": {
                  "statusCode": 400,
                  "requestID": "req-1",
                  "headers": {
                    "Vary": "Accept-Encoding"
                  },
                  "body": "QmFkIHJlcXVlc3Q="
                }
              }
            } 
            """
                .trimIndent(),
        )

    assertThat(event).isInstanceOf(RawResponseEvent::class.java)

    val rawResponseEvent = event as RawResponseEvent
    assertThat(rawResponseEvent.response.statusCode).isEqualTo(400)
    assertThat(rawResponseEvent.response.requestID).isEqualTo("req-1")
    assertThat(rawResponseEvent.response.headers).isEqualTo(mapOf("Vary" to "Accept-Encoding"))
  }

  @Test
  fun `validate rawResponse toJson`() {
    val event =
        RawResponseEvent(
            response =
                Response(
                    requestID = "1e44c8ba-2107-4e52-b41f-25d4f59aae7c",
                    statusCode = 400,
                    headers =
                        mapOf(
                            "Vary" to "Accept-Encoding",
                            "Content-Length" to "11",
                            "cf-ray" to "962fbdcafc71ec27-SEA",
                            "Server" to "cloudflare",
                            "Content-Type" to "text/plain;charset=UTF-8",
                            "Date" to "Tue, 22 Jul 2025 03:09:48 GMT",
                        ),
                    body = "Bad request".toByteArray(),
                ),
        )
    val json = adapter.toJson(event)
    val expectedJson =
        """
        {"rawResponse":{"_0":{"requestID":"1e44c8ba-2107-4e52-b41f-25d4f59aae7c","statusCode":400,"headers":{"Vary":"Accept-Encoding","Content-Length":"11","cf-ray":"962fbdcafc71ec27-SEA","Server":"cloudflare","Content-Type":"text/plain;charset=UTF-8","Date":"Tue, 22 Jul 2025 03:09:48 GMT"},"body":"QmFkIHJlcXVlc3Q="}}}
        """
            .trimIndent()
            .replace("\n", "")
    assertThat(json.replace("\n", "")).isEqualTo(expectedJson)
  }

  @Test
  fun `validate proposedHumanReadableResponse fromJson`() {
    val event = adapter.fromJson(proposedHumanReadableResponseJson)
    assertThat(event).isInstanceOf(ProposedHumanReadableResponseEvent::class.java)
    val response = (event as ProposedHumanReadableResponseEvent).response
    assertThat(response.requestID).isEqualTo("abcd-1234")
    assertThat(response.statusCode).isEqualTo(200)
    assertThat(response.headers["Content-Type"]).isEqualTo("application/json")
    assertThat(response.body).isEqualTo("{\"message\":\"ok\"}")
  }

  @Test
  fun `validate proposedHumanReadableResponse toJson`() {
    val event =
        ProposedHumanReadableResponseEvent(
            response =
                Response(
                    requestID = "abcd-1234",
                    statusCode = 200,
                    headers = mapOf("Content-Type" to "application/json"),
                    body = "{\"message\":\"ok\"}",
                ),
        )
    val json = adapter.toJson(event)
    val expectedJson =
        """
        {"proposedHumanReadableResponse":{"_0":{"requestID":"abcd-1234","statusCode":200,"headers":{"Content-Type":"application/json"},"body":"{\"message\":\"ok\"}"}}}
        """
            .trimIndent()
            .replace("\n", "")
    assertThat(json.replace("\n", "")).isEqualTo(expectedJson)
  }

  private val proposedHumanReadableResponseJson =
      """
      {
        "proposedHumanReadableResponse": {
          "_0": {
            "statusCode": 200,
            "requestID": "abcd-1234",
            "headers": {
              "Content-Type": "application/json"
            },
            "body": "{\"message\":\"ok\"}"
          }
        }
      }
      """
          .trimIndent()
}
