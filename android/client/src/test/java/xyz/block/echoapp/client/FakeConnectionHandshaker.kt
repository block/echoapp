package xyz.block.echoapp.client

import android.net.LocalSocket
import xyz.block.echoapp.client.internal.ConnectionHandshaker
import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

class FakeConnectionHandshaker : ConnectionHandshaker, UnixDomainTunnelProvider {
  val events =
      MutableSharedFlow<ConnectionRequest?>(
          replay = 1,
          extraBufferCapacity = 1,
          onBufferOverflow = BufferOverflow.DROP_OLDEST,
      )
  var attachedClient: EchoClient? = null

  override fun attach(client: EchoClient) {
    attachedClient = client
  }

  override suspend fun startReceivingConnectionRequest(): Flow<ConnectionRequest?> =
      events.asSharedFlow()

  override fun stopReceivingConnectionRequest() = Unit

  override fun consumeAcceptedLocalSocket(): LocalSocket? {
    // Create a direct connection to the mock web server
    return try {
      // We need to get the connection request that was emitted
      // Since this is called after the connection request is emitted in the test,
      // we can access it from the shared flow
      val connectionRequest = events.replayCache.lastOrNull()
      if (connectionRequest != null) {
        val uri = java.net.URI(connectionRequest.serverUrl)
        val socket = Socket()
        socket.connect(InetSocketAddress(uri.host, uri.port))
        MockLocalSocket(socket)
      } else {
        null
      }
    } catch (e: Exception) {
      null
    }
  }

  // Mock LocalSocket that wraps a regular Socket
  private class MockLocalSocket(private val socket: Socket) : LocalSocket() {
    override fun getInputStream() = socket.getInputStream()

    override fun getOutputStream() = socket.getOutputStream()

    override fun close() = socket.close()

    override fun isConnected() = socket.isConnected

    override fun isClosed() = socket.isClosed

    override fun setSoTimeout(timeout: Int) {
      socket.soTimeout = timeout
    }

    override fun getSoTimeout() = socket.soTimeout
  }
}
