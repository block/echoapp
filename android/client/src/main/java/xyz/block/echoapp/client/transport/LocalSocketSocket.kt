package xyz.block.echoapp.client.transport

import android.net.LocalSocket
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.Socket
import java.net.SocketAddress

/**
 * A [Socket] implementation that delegates IO to an Android [LocalSocket].
 *
 * This allows OkHttp to treat a connected [LocalSocket] as a regular TCP socket for the purpose of
 * HTTP/WebSocket handshakes and subsequent framing.
 */
internal class LocalSocketSocket(
    private val localSocket: LocalSocket,
) : Socket() {
  @Volatile private var closed: Boolean = false

  override fun connect(endpoint: SocketAddress?) {
    // LocalSocket is already connected by the time we receive it.
  }

  override fun connect(
      endpoint: SocketAddress?,
      timeout: Int,
  ) {
    // LocalSocket is already connected by the time we receive it.
  }

  override fun isConnected(): Boolean = !closed

  override fun isClosed(): Boolean = closed

  override fun close() {
    if (!closed) {
      try {
        localSocket.close()
      } catch (_: Throwable) {
        // Swallow; closing
      } finally {
        closed = true
      }
    }
  }

  override fun getInputStream(): InputStream = localSocket.inputStream

  override fun getOutputStream(): OutputStream = localSocket.outputStream

  override fun setSoTimeout(timeout: Int) {
    localSocket.soTimeout = timeout
  }

  override fun getSoTimeout(): Int = localSocket.soTimeout

  override fun shutdownInput() {
    // Not supported explicitly by LocalSocket; no-op to preserve the tunnel
  }

  override fun shutdownOutput() {
    // Not supported explicitly by LocalSocket; no-op to preserve the tunnel
  }

  // Socket options often configured by OkHttp; implement as no-ops where unsupported
  override fun setTcpNoDelay(on: Boolean) {
    // Not applicable for LocalSocket
  }

  override fun getTcpNoDelay(): Boolean = true

  override fun setKeepAlive(on: Boolean) {
    // Not applicable for LocalSocket
  }

  override fun getKeepAlive(): Boolean = false

  override fun setSoLinger(
      on: Boolean,
      linger: Int,
  ) {
    // Not applicable for LocalSocket
  }

  override fun getSoLinger(): Int = -1

  override fun getInetAddress(): InetAddress? = null

  override fun getLocalAddress(): InetAddress = InetAddress.getLoopbackAddress()

  override fun getPort(): Int = 0

  override fun getLocalPort(): Int = 0
}
