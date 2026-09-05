package xyz.block.echoapp.plugin.buffered

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class, DelicateCoroutinesApi::class)
class BufferedClientPluginTest {
  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val plugin = FakeBufferedClientPlugin()

  @Test
  fun `buffers sent data before connection is established, then flushes buffer on connection`() =
      runTest {
        val expectedData = "Hi there"
        val expectedRowId = "test-row"
        val expectedRowColumnItems = mapOf("key" to "value")

        with(plugin) {
          testSend(expectedData)
          testSendTableRow(
              id = expectedRowId,
              columnItems = expectedRowColumnItems,
          )
          pluginConnection.expectNoSentData()
          assertThat(buffer.isEmpty).isFalse()

          onConnect(backgroundScope, pluginConnection)
          assertThat(pluginConnection.awaitSentData()).isEqualTo("Hi there")
          assertThat(pluginConnection.awaitSentData())
              .isEqualTo(
                  "{\"id\":\"fake-row-id-1\",\"columnItems\":{\"key\":\"value\"}}",
              )
          assertThat(buffer.isEmpty).isTrue()
        }
      }

  @Test
  fun `does not buffer data while connection is established`() = runTest {
    val expectedData = "Hi there"
    val expectedRowId = "test-row"
    val expectedRowColumnItems = mapOf("key" to "value")

    with(plugin) {
      onConnect(backgroundScope, pluginConnection)
      testSend(expectedData)
      testSendTableRow(
          id = expectedRowId,
          columnItems = expectedRowColumnItems,
      )
      assertThat(buffer.isEmpty).isFalse()
      assertThat(pluginConnection.awaitSentData()).isEqualTo("Hi there")
      assertThat(pluginConnection.awaitSentData())
          .isEqualTo(
              "{\"id\":\"fake-row-id-1\",\"columnItems\":{\"key\":\"value\"}}",
          )
      assertThat(buffer.isEmpty).isTrue()
    }
  }

  @Test
  fun `does not close channel on disconnect`() = runTest {
    val expectedData = "Hi there"
    var closableScope = TestScope()

    with(plugin) {
      testSend(expectedData)
      closableScope.runCurrent()
      assertThat(buffer.isEmpty).isFalse()
      assertThat(buffer.isClosedForSend).isFalse()

      onConnect(closableScope, pluginConnection)
      closableScope.runCurrent()
      assertThat(pluginConnection.awaitSentData()).isEqualTo(expectedData)
      assertThat(buffer.isEmpty).isTrue()
      assertThat(buffer.isClosedForSend).isFalse()
      closableScope.cancel()

      testSend(expectedData)
      closableScope.runCurrent()
      assertThat(buffer.isEmpty).isFalse()
      assertThat(buffer.isClosedForSend).isFalse()
      pluginConnection.expectNoSentData()

      closableScope = TestScope()
      onConnect(closableScope, pluginConnection)
      closableScope.runCurrent()
      assertThat(pluginConnection.awaitSentData()).isEqualTo(expectedData)
      assertThat(buffer.isEmpty).isTrue()
      closableScope.cancel()
    }
  }

  private class FakeBufferedClientPlugin : BufferedClientPlugin(bufferSize = 2) {
    override val pluginIdentifier: String = "xyz.block.fake-plugin"

    /** Exposes the underlying protected method. */
    suspend fun testSend(data: String) = send(data)

    /** Exposes the underlying protected method. */
    suspend fun testSendTableRow(
        id: String?,
        columnItems: Map<String, String>,
    ) =
        sendTableRow(
            id = id,
            columnItems = columnItems,
        )
  }
}
