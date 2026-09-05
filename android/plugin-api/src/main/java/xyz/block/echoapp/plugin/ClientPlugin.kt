package xyz.block.echoapp.plugin

import kotlinx.coroutines.CoroutineScope

/**
 * Interface for Echo plugins that run in mobile apps. Provides a mechanism to send and receive data
 * related to a specific Echo plugin.
 */
interface ClientPlugin {
  /** A unique identifier for the plugin, which must match the ID of a desktop plugin. */
  val pluginIdentifier: String

  /**
   * Invoked when `EchoClient` establishes a connection, giving the plugin a handle to send data to
   * the desktop app.
   */
  fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  )

  /**
   * Invoked when the desktop app sends data to the client plugin. This is decoded from Base64, and
   * is generally JSON.
   */
  @Deprecated("Use PluginConnection.onEventReceived() instead.")
  suspend fun onDataReceived(data: String) = Unit

  /** Invoked when the connection to the desktop app is closed. */
  suspend fun onDisconnect() = Unit

  /** Invoked when the plugin becomes active (comes into view) in the desktop app. */
  @Deprecated("Use PluginConnection.isDesktopPluginActive instead.")
  suspend fun onDesktopPluginActive() = Unit

  /** Invoked when the plugin becomes inactive (is no longer in view) in the desktop app. */
  @Deprecated("Use PluginConnection.isDesktopPluginActive instead.")
  suspend fun onDesktopPluginInactive() = Unit
}
