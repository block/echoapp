package xyz.block.echoapp.client.transport

import xyz.block.echoapp.client.UnixDomainTunnelProvider
import java.io.IOException
import java.net.InetAddress
import java.net.Socket
import javax.net.SocketFactory

/**
 * A [SocketFactory] that supplies a [Socket] backed by an accepted Android
 * [android.net.LocalSocket] from a [UnixDomainTunnelProvider].
 */
class TunnelSocketFactory(
    private val tunnelProvider: UnixDomainTunnelProvider,
) : SocketFactory() {
  override fun createSocket(): Socket {
    val localSocket =
        tunnelProvider.consumeAcceptedLocalSocket()
            ?: throw IOException("No available tunnel socket")
    return LocalSocketSocket(localSocket)
  }

  override fun createSocket(
      host: String?,
      port: Int,
  ): Socket {
    return createSocket()
  }

  override fun createSocket(
      host: String?,
      port: Int,
      localHost: InetAddress?,
      localPort: Int,
  ): Socket {
    return createSocket()
  }

  override fun createSocket(
      host: InetAddress?,
      port: Int,
  ): Socket {
    return createSocket()
  }

  override fun createSocket(
      address: InetAddress?,
      port: Int,
      localAddress: InetAddress?,
      localPort: Int,
  ): Socket {
    return createSocket()
  }
}
