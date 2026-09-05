package xyz.block.echoapp.client

import app.cash.turbine.test
import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.client.ClientState.Advertising
import xyz.block.echoapp.client.ClientState.Connected
import xyz.block.echoapp.client.ClientState.Disconnected
import xyz.block.echoapp.client.internal.ClientPluginLifecycleEvent.ACTIVE
import xyz.block.echoapp.client.internal.ClientPluginLifecycleEvent.INACTIVE
import xyz.block.echoapp.client.internal.PluginPayload
import xyz.block.echoapp.client.utils.SuspendingWebSocketListener
import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.tables.EchoTableRow
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import xyz.block.echoapp.plugin.utils.loggers.StdOutEchoDebugLogger
import java.net.InetAddress
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.ByteString.Companion.encodeUtf8
import okio.ByteString.Companion.toByteString
import org.junit.After
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class EchoClientTest {
  private val mockwebserver = MockWebServer()
  private val testDispatcher = UnconfinedTestDispatcher()
  private val nsdAdvertiser = FakeConnectionHandshaker()

  @Before
  fun setUp() {
    mockwebserver.start(
        InetAddress.getLocalHost(),
        port = TEST_SERVER_PORT,
    )
    EchoDebugLogger.install(StdOutEchoDebugLogger)
  }

  @After
  fun tearDown() {
    mockwebserver.shutdown()
  }

  @Test
  fun `connection handshaker gets attached to client on build`() {
    val client = createEchoClient()
    val connectionHandshaker = client.connectionHandshaker
    assertThat((connectionHandshaker as FakeConnectionHandshaker).attachedClient)
        .isSameInstanceAs(client)
  }

  @Test
  fun `new client has no plugins installed`() {
    assertThat(createEchoClient().clientPlugins).isEmpty()
  }

  @Test
  fun `add plugin updates plugin list`() {
    val client = createEchoClient(FakeClientPlugin())

    assertThat(client.clientPlugins).hasSize(1)
  }

  @Test
  fun `echo client start searches for app clients`() = runTest {
    val client = createEchoClient()
    client.clientState.test {
      assertThat(awaitItem()).isEqualTo(Disconnected)

      client.start()

      assertThat(awaitItem()).isEqualTo(Advertising)
    }
  }

  @Test
  fun `echo client stop emits disconnection`() = runTest {
    val client = createEchoClient()
    client.clientState.test {
      assertThat(awaitItem()).isEqualTo(Disconnected)

      client.start()

      assertThat(awaitItem()).isEqualTo(Advertising)

      client.stop()
      assertThat(awaitItem()).isEqualTo(Disconnected)
      cancel()
    }
  }

  @Test
  fun `echo client connects to app client`() = runTest {
    val fakeClientPlugin = FakeClientPlugin()
    val client = createEchoClient(fakeClientPlugin)

    client.clientState.test {
      awaitItem()

      client.start()
      assertThat(fakeClientPlugin.connection).isNull()

      awaitItem()

      nsdAdvertiser.events.tryEmit(
          ConnectionRequest(
              "ws://${mockwebserver.hostName}:$TEST_SERVER_PORT",
          ),
      )

      val serverListener = object : WebSocketListener() {}
      mockwebserver.enqueue(MockResponse().withWebSocketUpgrade(serverListener))

      assertThat(awaitItem()).isEqualTo(Connected)
      assertThat(fakeClientPlugin.connection).isNotNull()

      client.stop()
      assertThat(awaitItem()).isEqualTo(Disconnected)
      cancel()
    }
  }

  @Test
  fun `web socket close disconnects client and restarts`() = runTest {
    val fakeClientPlugin = FakeClientPlugin()
    val client = createEchoClient(fakeClientPlugin)

    client.clientState.test {
      awaitItem()

      client.start()
      awaitItem()

      nsdAdvertiser.events.tryEmit(
          ConnectionRequest(
              "ws://${mockwebserver.hostName}:$TEST_SERVER_PORT",
          ),
      )

      val serverListener = SuspendingWebSocketListener()
      mockwebserver.enqueue(MockResponse().withWebSocketUpgrade(serverListener))

      awaitItem()

      val socket = serverListener.awaitSocketOpened()
      socket.close(1000, "Normal closure")

      assertThat(awaitItem()).isEqualTo(Disconnected)

      // Client is restarted and can accept new connections
      assertThat(awaitItem()).isEqualTo(Advertising)
      nsdAdvertiser.events.tryEmit(
          ConnectionRequest(
              "ws://${mockwebserver.hostName}:$TEST_SERVER_PORT",
          ),
      )
      val newServerListener = SuspendingWebSocketListener()
      mockwebserver.enqueue(MockResponse().withWebSocketUpgrade(newServerListener))

      newServerListener.awaitSocketOpened()
      assertThat(awaitItem()).isEqualTo(Connected)
    }
  }

  @Test
  fun `echo client can send data to the server`() = runTest {
    val fakeClientPlugin = FakeClientPlugin()
    val client = createEchoClient(fakeClientPlugin)

    client.clientState.test {
      awaitItem()
      client.start()
      awaitItem()

      nsdAdvertiser.events.tryEmit(
          ConnectionRequest(
              "ws://${mockwebserver.hostName}:$TEST_SERVER_PORT",
          ),
      )

      val serverListener = SuspendingWebSocketListener()
      mockwebserver.enqueue(MockResponse().withWebSocketUpgrade(serverListener))

      assertThat(awaitItem()).isEqualTo(Connected)
      assertThat(fakeClientPlugin.connection).isNotNull()

      assertThat(serverListener.awaitMessage().utf8())
          .isEqualTo("{\"client_plugin_ids\":[\"noop-plugin\"]}")

      val fakeData = "{\"hello\":\"world\"}"
      backgroundScope.launch { assertThat(fakeClientPlugin.connection!!.send(fakeData)).isTrue() }
      assertThat(serverListener.awaitMessage().utf8())
          .isEqualTo(
              "{\"plugin_id\":\"noop-plugin\",\"data\":\"eyJoZWxsbyI6IndvcmxkIn0=\"}",
          )

      client.stop()
      assertThat(awaitItem()).isEqualTo(Disconnected)
      cancel()
    }
  }

  @Test
  fun `echo client can send table row to the server`() = runTest {
    val fakeClientPlugin = FakeClientPlugin()
    val client = createEchoClient(fakeClientPlugin)

    client.clientState.test {
      awaitItem()
      client.start()
      awaitItem()

      nsdAdvertiser.events.tryEmit(
          ConnectionRequest(
              "ws://${mockwebserver.hostName}:$TEST_SERVER_PORT",
          ),
      )

      val serverListener = SuspendingWebSocketListener()
      mockwebserver.enqueue(MockResponse().withWebSocketUpgrade(serverListener))

      assertThat(awaitItem()).isEqualTo(Connected)
      assertThat(fakeClientPlugin.connection).isNotNull()

      assertThat(serverListener.awaitMessage().utf8())
          .isEqualTo("{\"client_plugin_ids\":[\"noop-plugin\"]}")

      val row =
          EchoTableRow(
              id = "fake-row-id",
              columnItems = mapOf("Column" to "value"),
          )
      launch {
        assertThat(
                fakeClientPlugin.connection!!.sendTableRow(
                    id = row.id,
                    columnItems = row.columnItems,
                ),
            )
            .isTrue()
      }

      assertThat(serverListener.awaitMessage().utf8())
          .isEqualTo(
              "{\"plugin_id\":\"noop-plugin\"," +
                  "\"data\":\"eyJpZCI6ImZha2Utcm93LWlkIiwiY29sdW1uSXRlbXMiOnsiQ29sdW1uIjoidmFsdWUifX0=\"}",
          )

      client.stop()
      assertThat(awaitItem()).isEqualTo(Disconnected)
      cancel()
    }
  }

  @Test
  fun `plugin receives events from websocket`() = runTest {
    val fakeClientPlugin = FakeClientPlugin()
    val client = createEchoClient(fakeClientPlugin)

    client.clientState.test {
      awaitItem()

      client.start()
      awaitItem()

      nsdAdvertiser.events.tryEmit(
          ConnectionRequest(
              "ws://${mockwebserver.hostName}:$TEST_SERVER_PORT",
          ),
      )

      val serverListener = SuspendingWebSocketListener()
      mockwebserver.enqueue(MockResponse().withWebSocketUpgrade(serverListener))

      awaitItem()

      val socket = serverListener.awaitSocketOpened()

      fakeClientPlugin.connection!!.isDesktopPluginActive.test {
        assertThat(awaitItem()).isFalse() // Initial value

        socket.sendPayload(
            fakeClientPlugin.pluginIdentifier,
            ACTIVE.toString().encodeUtf8().base64(),
        )

        assertThat(awaitItem()).isTrue()

        socket.sendPayload(
            fakeClientPlugin.pluginIdentifier,
            INACTIVE.toString().encodeUtf8().base64(),
        )

        assertThat(awaitItem()).isFalse()
      }

      fakeClientPlugin.connection!!.onDataReceived.test {
        // Send message for a different plugin
        socket.sendPayload(
            "differentPlugin",
            "randomData1".encodeUtf8().base64(),
        )
        expectNoEvents()

        val dataPayload = "randomData2"
        socket.sendPayload(
            fakeClientPlugin.pluginIdentifier,
            dataPayload.encodeUtf8().base64(),
        )
        assertThat(awaitItem()).isEqualTo(dataPayload)
      }

      client.stop()
      assertThat(awaitItem()).isEqualTo(Disconnected)
      cancel()
    }
  }

  private fun createEchoClient(vararg plugins: ClientPlugin): EchoClient {
    return EchoClient.Builder(
            appIdentifier = TEST_APP_IDENTIFIER,
            deviceIdentifierResolver = { TEST_DEVICE_IDENTIFIER },
            deviceNameResolver = { TEST_DEVICE_NAME },
            connectionHandshaker = nsdAdvertiser,
            okHttpClient = OkHttpClient.Builder().build(),
        )
        .ioContext(testDispatcher)
        .addPlugins(*plugins)
        .build()
  }

  private fun WebSocket.sendPayload(
      pluginId: String,
      data: String,
  ) {
    val payload = PluginPayload(pluginId, data)
    val json = EchoClient.payloadAdapter.toJson(payload)
    send(json.toByteArray().toByteString())
  }

  companion object {
    private const val TEST_APP_IDENTIFIER = "xyz.block.echoapp.client.test"
    private const val TEST_DEVICE_IDENTIFIER = "deviceIdentifier"
    private const val TEST_DEVICE_NAME = "deviceName"
    private const val TEST_SERVER_PORT = 9999
  }
}
