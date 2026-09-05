package xyz.block.echoapp.plugin.appinfo

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

class AppInfoPluginTest {
  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val plugin = AppInfoPlugin {
    scope("Tokens") {
      entry("Merchant", "ABCD")
      entry("Unit", "EFGH")
    }
    scope("Device") {
      entry("Manufacturer", "Google")
      entry("Model", "Pixel 8 Pro")
    }
  }

  @Test
  fun `app info plugin has expected ID`() {
    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.appinfo")
  }

  @Test
  fun `app info plugin sends app info on connection, and again when requested`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "[{\"scope\":\"Tokens\",\"key\":\"Merchant\",\"value\":\"ABCD\"}," +
                "{\"scope\":\"Tokens\",\"key\":\"Unit\",\"value\":\"EFGH\"}," +
                "{\"scope\":\"Device\",\"key\":\"Manufacturer\",\"value\":\"Google\"}," +
                "{\"scope\":\"Device\",\"key\":\"Model\",\"value\":\"Pixel 8 Pro\"}]",
        )

    pluginConnection.expectNoSentData()
    plugin.sendLatestAppInfo()
    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "[{\"scope\":\"Tokens\",\"key\":\"Merchant\",\"value\":\"ABCD\"}," +
                "{\"scope\":\"Tokens\",\"key\":\"Unit\",\"value\":\"EFGH\"}," +
                "{\"scope\":\"Device\",\"key\":\"Manufacturer\",\"value\":\"Google\"}," +
                "{\"scope\":\"Device\",\"key\":\"Model\",\"value\":\"Pixel 8 Pro\"}]",
        )
  }
}
