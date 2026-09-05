package xyz.block.echoapp.plugin

import xyz.block.echoapp.plugin.internal.ByteArrayAdapter
import xyz.block.echoapp.plugin.internal.ByteStringAdapter
import xyz.block.echoapp.plugin.internal.NumberAdapter
import xyz.block.echoapp.plugin.internal.UriAdapter
import xyz.block.echoapp.plugin.tables.EchoTableRow
import com.squareup.moshi.Moshi
import kotlin.reflect.KClass
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

/**
 * Represents a tunnel for sending messages to the Echo desktop app, for a specific plugin.
 * [PluginConnection] is provided to each enabled [ClientPlugin] when `EchoClient` establishes a
 * connection (via [ClientPlugin.onConnect]).
 */
interface PluginConnection {
  /** Stores and emits changes to whether or not the desktop plugin is active (in view). */
  val isDesktopPluginActive: StateFlow<Boolean>

  /**
   * Send some string-encoded [data] to the Echo desktop app.
   *
   * @return `true` if the message was sent successfully.
   */
  fun send(data: String): Boolean

  /**
   * Serializes a [model] using an adapter for the given [typeForAdapter], and sends it to the Echo
   * desktop app.
   *
   * @return `true` if the message was sent successfully.
   */
  fun send(
      typeForAdapter: KClass<*>,
      model: Any,
  ): Boolean

  /**
   * Sends an encoded [EchoTableRow] to the Echo desktop app, using the [id] and [columnItems]
   * provided. If [id] is left null, a random ID is generated.
   *
   * @return `true` if the message was sent successfully.
   */
  fun sendTableRow(
      id: String? = null,
      columnItems: Map<String, String>,
  ): Boolean

  /**
   * Emits when an event of the given [type] is received from the desktop app. Events of other types
   * are ignored and may be received by other collectors.
   */
  fun <T : Any> onEventReceived(type: KClass<T>): Flow<T>

  companion object {
    val echoMoshi: Moshi =
        Moshi.Builder()
            .add(ByteArrayAdapter())
            .add(ByteStringAdapter())
            .add(UriAdapter())
            .add(NumberAdapter())
            .build()
  }
}

/**
 * Serializes a [model] and sends it to the Echo desktop app. Note that the generic type [T] must
 * match the type in which a Moshi adapter should be queried for; if your event model is a sealed
 * interface or class, you should specify the parent type as [T] rather than the child event class.
 *
 * @return `true` if the message was sent successfully.
 */
inline fun <reified T : Any> PluginConnection.send(model: T): Boolean = send(T::class, model)

/**
 * Emits when an event of the given type [T] is received from the desktop app. Events of other types
 * are ignored and may be received by other collectors.
 */
inline fun <reified T : Any> PluginConnection.onEventReceived(): Flow<T> = onEventReceived(T::class)
