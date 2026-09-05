package xyz.block.echoapp.client.internal

import xyz.block.echoapp.client.EchoClient
import xyz.block.echoapp.client.UniqueGenerator
import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.tables.EchoTableRow
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.adapter
import kotlin.coroutines.CoroutineContext
import kotlin.reflect.KClass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.mapNotNull
import org.jetbrains.annotations.VisibleForTesting

/**
 * The "real" implementation of [PluginConnection], created by [EchoClient] per plugin when a
 * connection to the desktop app is established.
 *
 * The interface is surfaced to [ClientPlugin] implementations via [ClientPlugin.onConnect].
 * Responsible for communication with the desktop app, as well as caching things per plugin.
 */
@OptIn(ExperimentalStdlibApi::class)
internal class PluginConnectionImpl(
    coroutineContext: CoroutineContext,
    onDataReceivedBufferSize: Int,
    private val pluginIdentifier: String,
    private val uniqueGenerator: UniqueGenerator,
    private val sendToSocket: (json: String) -> Boolean,
) : PluginConnection {
  private val coroutineScope = CoroutineScope(coroutineContext)
  private val payloadAdapter = echoMoshi.adapter<PluginPayload>()
  private val tableRowAdapter = echoMoshi.adapter<EchoTableRow>()

  @VisibleForTesting
  internal val onDataReceived =
      MutableSharedFlow<String>(extraBufferCapacity = onDataReceivedBufferSize)

  override val isDesktopPluginActive = MutableStateFlow(false)

  fun notifyOnConnect(plugin: ClientPlugin) {
    plugin.onConnect(coroutineScope, this)
  }

  suspend fun notifyDataReceived(data: String) {
    onDataReceived.emit(data)
  }

  suspend fun notifyOnDisconnect(plugin: ClientPlugin) {
    isDesktopPluginActive.value = false
    coroutineScope.cancel()
    plugin.onDisconnect()
  }

  override fun send(data: String): Boolean {
    val pluginPayload =
        PluginPayload(
            pluginId = pluginIdentifier,
            data = data.encodeToBase64String(),
        )
    val payload = payloadAdapter.toJson(pluginPayload)
    return sendToSocket(payload)
  }

  override fun send(
      typeForAdapter: KClass<*>,
      model: Any,
  ): Boolean {
    val adapter = echoMoshi.adapter(typeForAdapter.java) as JsonAdapter<Any>
    return send(adapter.toJson(model))
  }

  override fun sendTableRow(
      id: String?,
      columnItems: Map<String, String>,
  ): Boolean {
    val row =
        EchoTableRow(
            id = id ?: uniqueGenerator(),
            columnItems = columnItems,
        )
    return send(tableRowAdapter.toJson(row))
  }

  override fun <T : Any> onEventReceived(type: KClass<T>): Flow<T> {
    val adapter = echoMoshi.adapter(type.java)
    return onDataReceived.mapNotNull { data -> adapter.fromJson(data) }
  }
}
