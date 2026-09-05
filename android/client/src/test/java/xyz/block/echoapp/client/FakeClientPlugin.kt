package xyz.block.echoapp.client

import xyz.block.echoapp.client.internal.PluginConnectionImpl
import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import kotlinx.coroutines.CoroutineScope

internal class FakeClientPlugin : ClientPlugin {
  override val pluginIdentifier: String = "noop-plugin"

  var connection: PluginConnectionImpl? = null
    private set

  override fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  ) {
    this@FakeClientPlugin.connection = connection as PluginConnectionImpl
  }

  override suspend fun onDisconnect() {
    this.connection = null
  }
}
