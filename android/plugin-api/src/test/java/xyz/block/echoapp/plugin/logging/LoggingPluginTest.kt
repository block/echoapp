package xyz.block.echoapp.plugin.logging

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.logging.Priority.INFO
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

class LoggingPluginTest {
  private val fakeCurrentTimestamp = "10:44:00.123"

  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val plugin =
      LoggingPlugin(
          currentTimestampProvider = { fakeCurrentTimestamp },
      )

  @Test
  fun `logging plugin has expected ID`() {
    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.logging")
  }

  @Test
  fun `logging plugin sends log events over the connection`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)

    pluginConnection.expectNoSentData()
    plugin.log(
        priority = INFO,
        tag = "Test",
        message = "Hello, world!",
        throwable = Exception("Test error"),
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"id\":\"fake-row-id-1\",\"columnItems\":{" +
                "\"Time\":\"10:44:00.123\"," +
                "\"Priority\":\"INFO\"," +
                "\"Tag\":\"Test\"," +
                "\"Message\":\"Hello, world! java.lang.Exception: Test error\"" +
                "}}",
        )
  }
}
