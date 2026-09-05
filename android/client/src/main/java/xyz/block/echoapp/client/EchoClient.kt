package xyz.block.echoapp.client

import android.content.Context
import xyz.block.echoapp.client.ClientState.Advertising
import xyz.block.echoapp.client.ClientState.Connected
import xyz.block.echoapp.client.ClientState.Disconnected
import xyz.block.echoapp.client.DeviceIdentifierResolver.DefaultFromAndroidId
import xyz.block.echoapp.client.DeviceNameResolver.DefaultFromBuild
import xyz.block.echoapp.client.internal.ClientInfoPayload
import xyz.block.echoapp.client.internal.ClientPluginLifecycleEvent
import xyz.block.echoapp.client.internal.ClientPluginLifecycleEvent.ACTIVE
import xyz.block.echoapp.client.internal.ClientPluginLifecycleEvent.INACTIVE
import xyz.block.echoapp.client.internal.ConnectionHandshaker
import xyz.block.echoapp.client.internal.PluginConnectionImpl
import xyz.block.echoapp.client.internal.PluginPayload
import xyz.block.echoapp.client.internal.RealNsdAdvertiser
import xyz.block.echoapp.client.internal.SocketEvent
import xyz.block.echoapp.client.internal.SocketEvent.OnClose
import xyz.block.echoapp.client.internal.SocketEvent.OnMessage
import xyz.block.echoapp.client.internal.SocketEvent.OnOpen
import xyz.block.echoapp.client.internal.decodeBase64ToString
import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import com.squareup.moshi.JsonDataException
import com.squareup.moshi.adapter
import java.util.UUID
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.encodeUtf8
import okio.ByteString.Companion.toByteString
import org.jetbrains.annotations.VisibleForTesting

typealias UniqueGenerator = () -> String

/**
 * Used by mobile apps to make themselves discoverable to the Echo desktop app. Enables the desktop
 * app to connect to the mobile app, to communicate with provided [clientPlugins].
 *
 * val client = EchoClient.Builder(context, "${Build.MANUFACTURER} ${Build.MODEL}") .addPlugins(…)
 * .build()
 *
 * // Make the mobile app discoverable, and accept connections. client.start()
 *
 * // Shuts the client down, stopping discoverability and closing connections. client.stop()
 */
class EchoClient
private constructor(
    internal val appIdentifier: String,
    internal val connectionHandshaker: ConnectionHandshaker,
    internal val deviceIdentifierResolver: DeviceIdentifierResolver,
    internal val deviceNameResolver: DeviceNameResolver,
    private val ioContext: CoroutineContext,
    private val uniqueGenerator: UniqueGenerator,
    private val okHttpClient: OkHttpClient,
    @VisibleForTesting internal val clientPlugins: Set<ClientPlugin>,
    private val onDataReceivedBufferSize: Int,
) {
  private val clientStateFlow = MutableStateFlow<ClientState>(Disconnected)
  private val coroutineScope: CoroutineScope = CoroutineScope(ioContext)
  private val pluginConnectionCache = mutableMapOf<ClientPlugin, PluginConnectionImpl>()

  private var connectionJob: Job? = null
    set(value) {
      field?.cancel()
      field = value
    }

  // Non-null when the connection is open
  private var webSocket: WebSocket? = null

  /** Used to constructor [EchoClient] instances. */
  @Suppress("unused")
  class Builder
  @VisibleForTesting
  internal constructor(
      private val appIdentifier: String,
      private val deviceIdentifierResolver: DeviceIdentifierResolver,
      private val deviceNameResolver: DeviceNameResolver,
      private val connectionHandshaker: ConnectionHandshaker,
      private val okHttpClient: OkHttpClient,
  ) {
    /** Constructor for using Unix Domain Socket. */
    constructor(
        context: Context,
        deviceIdentifierResolver: DeviceIdentifierResolver = DefaultFromAndroidId(context),
        deviceNameResolver: DeviceNameResolver = DefaultFromBuild,
        connectionHandshaker: ConnectionHandshaker = RealNsdAdvertiser(context),
        okHttpClient: OkHttpClient = OkHttpClient.Builder().build(),
    ) : this(
        appIdentifier = context.packageName,
        deviceIdentifierResolver = deviceIdentifierResolver,
        deviceNameResolver = deviceNameResolver,
        connectionHandshaker = connectionHandshaker,
        okHttpClient = okHttpClient,
    )

    private var ioContext: CoroutineContext = Dispatchers.IO

    private var uniqueGenerator: UniqueGenerator = { UUID.randomUUID().toString() }
    private val clientPlugins = mutableSetOf<ClientPlugin>()
    private var onDataReceivedBufferSize: Int = DEFAULT_ON_DATA_RECEIVED_BUFFER_SIZE

    /** Overrides the IO coroutine context; defaults to [Dispatchers.IO]. */
    fun ioContext(ioContext: CoroutineContext) = apply { this.ioContext = ioContext }

    /** Overrides the UUID generator; defaults to [UUID.randomUUID]. */
    fun uniqueGenerator(uniqueGenerator: UniqueGenerator) = apply {
      this.uniqueGenerator = uniqueGenerator
    }

    /** Adds client plugins to be enabled. */
    fun addPlugins(vararg plugins: ClientPlugin) = apply { this.clientPlugins.addAll(plugins) }

    /** Sets the buffer size for receiving events from the desktop client, per plugin. */
    fun onDataReceivedBufferSize(size: Int) = apply { this.onDataReceivedBufferSize = size }

    fun build(): EchoClient =
        EchoClient(
                appIdentifier = appIdentifier,
                deviceIdentifierResolver = deviceIdentifierResolver,
                deviceNameResolver = deviceNameResolver,
                connectionHandshaker = connectionHandshaker,
                ioContext = ioContext,
                uniqueGenerator = uniqueGenerator,
                clientPlugins = clientPlugins,
                okHttpClient = okHttpClient,
                onDataReceivedBufferSize = onDataReceivedBufferSize,
            )
            .also { connectionHandshaker.attach(it) }
  }

  /** A [StateFlow] containing the latest state of the client; see [ClientState]. */
  val clientState: StateFlow<ClientState> = clientStateFlow.asStateFlow()

  /** Makes the app discoverable to the Echo desktop, automatically accepts connections. */
  fun start() {
    if (isStarted()) {
      EchoDebugLogger.debug(TAG, "EchoClient is already running")
      return
    }

    EchoDebugLogger.info(TAG, "Starting EchoClient")
    this.connectionJob =
        coroutineScope.launch {
          EchoDebugLogger.debug(TAG, "Waiting for connection...")
          val connectionRequest =
              connectionHandshaker
                  .startReceivingConnectionRequest()
                  .onStart { clientStateFlow.emit(Advertising) }
                  .first()
          EchoDebugLogger.debug(TAG, "Received connection...")

          if (connectionRequest != null) {
            val serverUrl = connectionRequest.serverUrl
            EchoDebugLogger.debug(TAG, "Connecting to $serverUrl")
            connect(serverUrl = serverUrl)
          } else {
            EchoDebugLogger.warn(TAG, "Could not handle connection request")
          }
        }
  }

  /** Stops discoverability and closes any connections. */
  fun stop() {
    if (!isStarted()) return
    EchoDebugLogger.debug(TAG, "Stopping EchoClient")
    connectionJob = null
    closeConnection()
  }

  private fun restart() {
    stop()
    start()
  }

  private fun sendClientInfoPayload() {
    webSocket?.let { socket ->
      val payload =
          clientInfoPayloadAdapter.toJson(
              ClientInfoPayload(pluginIds = clientPlugins.map { it.pluginIdentifier }),
          )
      socket.send(payload.encodeUtf8())
    }
  }

  private fun buildConnection(
      plugin: ClientPlugin,
      sendToSocket: (json: String) -> Boolean,
  ): PluginConnectionImpl {
    return PluginConnectionImpl(
        coroutineContext = ioContext,
        onDataReceivedBufferSize = onDataReceivedBufferSize,
        pluginIdentifier = plugin.pluginIdentifier,
        uniqueGenerator = uniqueGenerator,
        sendToSocket = sendToSocket,
    )
  }

  private suspend fun connect(serverUrl: String) {
    if (webSocket != null) {
      EchoDebugLogger.debug(TAG, "WebSocket connection already open")
      return
    }

    socketFlow(serverUrl).collect { event ->
      when (event) {
        is OnOpen -> {
          EchoDebugLogger.verbose(TAG, "onOpen")
          clientStateFlow.emit(Connected)
          clientPlugins.forEach { plugin ->
            val connection = buildConnection(plugin) { event.webSocket.send(it.encodeUtf8()) }
            connection.notifyOnConnect(plugin)
            pluginConnectionCache.put(plugin, connection)
          }
          sendClientInfoPayload()
        }

        is OnClose -> {
          EchoDebugLogger.verbose(TAG, "onClose")
          clientPlugins.forEach { plugin ->
            pluginConnectionCache[plugin]?.notifyOnDisconnect(plugin)
            pluginConnectionCache.remove(plugin)
          }
          // Start advertising again so device is available to connect to
          restart()
        }

        is OnMessage -> {
          try {
            val pluginPayload = payloadAdapter.fromJson(event.data.utf8())
            pluginPayload?.let {
              EchoDebugLogger.debug(
                  TAG,
                  "Received payload from plugin ${pluginPayload.pluginId} " +
                      "with ${pluginPayload.data} data",
              )

              clientPlugins
                  .firstOrNull { it.pluginIdentifier == pluginPayload.pluginId }
                  ?.let {
                    val decodedPayloadData = pluginPayload.data.decodeBase64ToString()
                    val pluginConnection = pluginConnectionCache[it]
                    when (ClientPluginLifecycleEvent.fromString(decodedPayloadData)) {
                      ACTIVE -> {
                        EchoDebugLogger.verbose(TAG, "Plugin ${pluginPayload.pluginId} is active")
                        it.onDesktopPluginActive()
                        pluginConnection?.isDesktopPluginActive?.value = true
                      }
                      INACTIVE -> {
                        EchoDebugLogger.verbose(TAG, "Plugin ${pluginPayload.pluginId} is inactive")
                        it.onDesktopPluginInactive()
                        pluginConnection?.isDesktopPluginActive?.value = false
                      }
                      null -> {
                        EchoDebugLogger.verbose(
                            TAG,
                            "Passing payload to plugin ${pluginPayload.pluginId}",
                        )
                        it.onDataReceived(decodedPayloadData)
                        pluginConnection?.notifyDataReceived(decodedPayloadData)
                            ?: EchoDebugLogger.warn(
                                tag = TAG,
                                message = "No connection cached for ${pluginPayload.pluginId}",
                            )
                      }
                    }
                  }
            }
          } catch (e: JsonDataException) {
            EchoDebugLogger.error(TAG, "Failed to parse payload", e)
          }
        }
      }
    }
  }

  private fun socketFlow(serverUrl: String): Flow<SocketEvent> = callbackFlow {
    val socketListener =
        object : WebSocketListener() {
          override fun onClosed(
              webSocket: WebSocket,
              code: Int,
              reason: String,
          ) {
            EchoDebugLogger.debug(TAG, "WebSocket onClosed. Code $code, reason $reason")
            trySendBlocking(OnClose)
          }

          override fun onClosing(
              webSocket: WebSocket,
              code: Int,
              reason: String,
          ) {
            EchoDebugLogger.debug(TAG, "WebSocket onClosing. Code $code, reason $reason")
            trySendBlocking(OnClose)
          }

          override fun onFailure(
              webSocket: WebSocket,
              t: Throwable,
              response: Response?,
          ) {
            EchoDebugLogger.debug(TAG, "WebSocket onFailure. Throwable $t, response $response")
            closeConnection()
          }

          override fun onMessage(
              webSocket: WebSocket,
              bytes: ByteString,
          ) {
            EchoDebugLogger.debug(TAG, "WebSocket onMessage. Bytes $bytes")
            trySendBlocking(OnMessage(bytes))
          }

          override fun onMessage(
              webSocket: WebSocket,
              text: String,
          ) {
            EchoDebugLogger.debug(TAG, "WebSocket onMessage. String $text")
            trySendBlocking(OnMessage(text.toByteArray().toByteString()))
          }

          override fun onOpen(
              webSocket: WebSocket,
              response: Response,
          ) {
            EchoDebugLogger.debug(TAG, "WebSocket onOpen. Response $response")
            trySendBlocking(OnOpen(webSocket))
          }
        }

    startConnection(serverUrl, socketListener)
    awaitClose { closeConnection() }
  }

  private fun startConnection(
      serverUrl: String,
      listener: WebSocketListener,
  ) {
    val request =
        Request.Builder()
            .url(getUrl(serverUrl))
            .header(APP_IDENTIFIER_HEADER, appIdentifier)
            .header(DEVICE_IDENTIFIER_HEADER, deviceIdentifierResolver.resolve())
            .header(DEVICE_NAME_HEADER, deviceNameResolver.resolve())
            .build()

    EchoDebugLogger.verbose(TAG, "WebSocket request is $request")
    webSocket =
        okHttpClient.newWebSocket(
            request = request,
            listener = listener,
        )
  }

  private fun getUrl(serverUrl: String): String {
    return if (connectionHandshaker is UnixDomainSocketServer) {
      // Rewrite the URL to localhost while preserving the path/query.
      val uri =
          try {
            java.net.URI(serverUrl)
          } catch (_: Throwable) {
            null
          }
      val path = uri?.rawPath ?: "/"
      val query = uri?.rawQuery?.let { "?$it" } ?: ""
      "ws://localhost$path$query"
    } else {
      serverUrl
    }
  }

  private fun closeConnection() {
    webSocket?.cancel()
    webSocket = null
    connectionHandshaker.stopReceivingConnectionRequest()
    clientStateFlow.tryEmit(Disconnected)
  }

  private fun isStarted(): Boolean = connectionJob?.isActive == true

  @OptIn(ExperimentalStdlibApi::class)
  @VisibleForTesting
  internal companion object {
    private const val TAG = "EchoClient"

    private const val APP_IDENTIFIER_HEADER = "Echo-App-Identifier"
    private const val DEVICE_IDENTIFIER_HEADER = "Echo-Device-Identifier"
    private const val DEVICE_NAME_HEADER = "Echo-Device-Name"
    private const val DEFAULT_ON_DATA_RECEIVED_BUFFER_SIZE = 32

    @VisibleForTesting internal val payloadAdapter = echoMoshi.adapter<PluginPayload>()

    private val clientInfoPayloadAdapter = echoMoshi.adapter<ClientInfoPayload>()
  }
}
