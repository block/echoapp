package xyz.block.echoapp.plugin.buffered

import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.buffered.BufferedClientPlugin.BufferEntry.BufferedData
import xyz.block.echoapp.plugin.buffered.BufferedClientPlugin.BufferEntry.BufferedModel
import xyz.block.echoapp.plugin.buffered.BufferedClientPlugin.BufferEntry.BufferedTableRow
import xyz.block.echoapp.plugin.collectIn
import kotlin.reflect.KClass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow
import org.jetbrains.annotations.VisibleForTesting

const val DEFAULT_BUFFER_SIZE = 100

/**
 * A special [ClientPlugin] that allows data to be sent via [send]/[sendTableRow] even before a
 * connection is established. The data is stored in memory and sent once a connection has been
 * established.
 */
@Suppress("unused")
abstract class BufferedClientPlugin(
    bufferSize: Int = DEFAULT_BUFFER_SIZE,
    onBufferOverflow: BufferOverflow = DROP_OLDEST,
) : ClientPlugin {
  @VisibleForTesting
  internal val buffer =
      Channel<BufferEntry>(
          capacity = bufferSize,
          onBufferOverflow = onBufferOverflow,
      )

  @OptIn(FlowPreview::class)
  override fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  ) {
    buffer.receiveAsFlow().collectIn(scope) { entry -> connection.send(entry) }
  }

  /**
   * Returns `true` if the given [data] was queued in the buffer (or delivered over the connection
   * if active). Returns `false` if the buffer is full, which will not happen by default since the
   * default [onBufferOverflow] strategy is [DROP_OLDEST].
   *
   * Prefer [send] where possible, for guaranteed delivery regardless of the overflow strategy. See
   * [Channel.trySend] for underlying docs.
   */
  fun trySend(data: String): Boolean {
    return tryEnqueue(BufferedData(data))
  }

  /**
   * Queues the given [data] in the buffer (or delivers it immediately over the connection if
   * active). Suspends if the buffer is full or does not exist.
   *
   * See [Channel.send] for underlying docs.
   */
  suspend fun send(data: String) {
    enqueue(BufferedData(data))
  }

  /**
   * Returns `true` if the given [model] was queued in the buffer (or delivered over the connection
   * if active). Returns `false` if the buffer is full, which will not happen by default since the
   * default [onBufferOverflow] strategy is [DROP_OLDEST].
   *
   * Prefer [send] where possible, for guaranteed delivery regardless of the overflow strategy. See
   * [Channel.trySend] for underlying docs.
   */
  fun trySend(
      typeForAdapter: KClass<*>,
      model: Any,
  ): Boolean {
    return tryEnqueue(BufferedModel(typeForAdapter, model))
  }

  /**
   * Queues the given [model] in the buffer (or delivers it immediately over the connection if
   * active). Suspends if the buffer is full or does not exist.
   *
   * See [Channel.send] for underlying docs.
   */
  suspend fun send(
      typeForAdapter: KClass<*>,
      model: Any,
  ) {
    enqueue(BufferedModel(typeForAdapter, model))
  }

  /**
   * Returns `true` if the table row was queued in the buffer (or delivered over the connection if
   * active). Returns `false` if the buffer is full, which will not happen by default since the
   * default [onBufferOverflow] strategy is [DROP_OLDEST].
   *
   * Prefer [send] where possible, for guaranteed delivery regardless of the overflow strategy. See
   * [Channel.trySend] for underlying docs.
   */
  fun trySendTableRow(
      id: String?,
      columnItems: Map<String, String>,
  ): Boolean {
    return tryEnqueue(
        BufferedTableRow(
            id = id,
            columnItems = columnItems,
        ),
    )
  }

  /**
   * Queues the given table row in the buffer (or delivers it immediately over the connection if
   * active). Suspends if the buffer is full or does not exist.
   *
   * See [Channel.send] for underlying docs.
   */
  suspend fun sendTableRow(
      id: String?,
      columnItems: Map<String, String>,
  ) {
    enqueue(
        BufferedTableRow(
            id = id,
            columnItems = columnItems,
        ),
    )
  }

  private fun tryEnqueue(entry: BufferEntry): Boolean = buffer.trySend(entry).isSuccess

  private suspend fun enqueue(entry: BufferEntry) = buffer.send(entry)

  private fun PluginConnection.send(entry: BufferEntry) {
    when (entry) {
      is BufferedData -> send(entry.data)
      is BufferedModel -> send(entry.typeForAdapter, entry.model)
      is BufferedTableRow ->
          sendTableRow(
              id = entry.id,
              columnItems = entry.columnItems,
          )
    }
  }

  /** Allows us to buffer data without making client plugins know how to encode plugin payload. */
  @VisibleForTesting
  internal sealed interface BufferEntry {
    data class BufferedData(val data: String) : BufferEntry

    data class BufferedModel(
        val typeForAdapter: KClass<*>,
        val model: Any,
    ) : BufferEntry

    data class BufferedTableRow(
        val id: String?,
        val columnItems: Map<String, String>,
    ) : BufferEntry
  }
}

/** See [BufferedClientPlugin.trySend]. */
inline fun <reified T : Any> BufferedClientPlugin.trySend(model: T): Boolean =
    trySend(
        typeForAdapter = T::class,
        model = model,
    )

/** See [BufferedClientPlugin.send]. */
suspend inline fun <reified T : Any> BufferedClientPlugin.send(model: T) =
    send(
        typeForAdapter = T::class,
        model = model,
    )
