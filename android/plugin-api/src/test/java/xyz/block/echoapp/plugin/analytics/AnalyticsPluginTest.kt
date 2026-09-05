package xyz.block.echoapp.plugin.analytics

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

class AnalyticsPluginTest {
  private val fakeTimestamp = "10:19:00.123"
  private val fakeUuid = "ABCD-EFGH-IJKL-MNOP"

  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val plugin =
      AnalyticsPlugin(
          currentTimestampProvider = { fakeTimestamp },
          uuidProvider = { fakeUuid },
      )

  @Test
  fun `analytics plugin has expected ID`() {
    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.analytics")
  }

  @Test
  fun `analytics plugin sends log events over the connection`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)

    pluginConnection.expectNoSentData()
    plugin.track(
        source = "CDP",
        eventName = "View Conversation",
        properties =
            mapOf(
                "transcriptId" to 1_024L,
                "medium" to "SMS",
            ),
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"id\":\"fake-row-id-1\",\"columnItems\":{" +
                "\"Time\":\"$fakeTimestamp\"," +
                "\"Source\":\"CDP\"," +
                "\"Event\":\"View Conversation\"," +
                "\"Properties\":\"{\\\"transcriptId\\\":1024,\\\"medium\\\":\\\"SMS\\\"}\"" +
                "}}",
        )
  }
}
