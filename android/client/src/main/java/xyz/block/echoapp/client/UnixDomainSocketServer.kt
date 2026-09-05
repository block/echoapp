package xyz.block.echoapp.client

import android.annotation.SuppressLint
import android.net.LocalServerSocket
import android.net.LocalSocket
import xyz.block.echoapp.client.internal.ConnectionHandshaker
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import com.squareup.moshi.adapter
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Advertises over a Unix Domain Socket and exposes the accepted [LocalSocket] to be reused as a
 * tunnel for subsequent OkHttp traffic.
 */
@OptIn(ExperimentalStdlibApi::class)
@SuppressLint("HardwareIds")
class UnixDomainSocketServer : ConnectionHandshaker, UnixDomainTunnelProvider {
  private val serverSocket = AtomicReference<LocalServerSocket?>(null)
  private val isAdvertising = AtomicBoolean(false)

  private lateinit var socketName: String

  // The most recently accepted LocalSocket kept open for tunneling
  private val acceptedLocalSocket = AtomicReference<LocalSocket?>(null)

  private companion object {
    const val TAG = "UnixDomainSocketServer"
    const val SERVER_NAME = "echo-server"
    val connectionAdapter = echoMoshi.adapter<ConnectionRequest>()
  }

  override fun attach(client: EchoClient) {
    socketName = "$SERVER_NAME-${client.deviceIdentifierResolver.resolve()}"
  }

  override suspend fun startReceivingConnectionRequest(): Flow<ConnectionRequest?> =
      callbackFlow {
            // Clean up any previous state before starting
            if (isAdvertising.get() || serverSocket.get() != null) {
              EchoDebugLogger.debug(
                  TAG, "Cleaning up previous advertising state for socket $socketName")
              cleanupSockets()
            }

            try {
              val socket = LocalServerSocket(socketName)
              serverSocket.set(socket)
              isAdvertising.set(true)
              EchoDebugLogger.debug(TAG, "Started advertising on Unix domain socket: $socketName")

              // Accept a single connection for handshake, keep the socket open for tunneling
              try {
                val acceptedSocket = socket.awaitConnection()
                EchoDebugLogger.debug(TAG, "Received connection on Unix domain socket")

                val connectionRequest =
                    try {
                      val reader = BufferedReader(InputStreamReader(acceptedSocket.inputStream))
                      val data = reader.readLine()
                      connectionAdapter.fromJson(data)
                    } catch (e: Exception) {
                      EchoDebugLogger.error(TAG, "Error decoding connection request!", e)
                      null
                    }

                // Preserve the connected LocalSocket for OkHttp to tunnel through
                acceptedLocalSocket.set(acceptedSocket)

                trySendBlocking(connectionRequest)
              } catch (e: Exception) {
                if (isAdvertising.get()) {
                  EchoDebugLogger.error(TAG, "Error accepting connection", e)
                }
              }
            } catch (e: Exception) {
              EchoDebugLogger.error(TAG, "Error starting Unix domain socket server", e)
              cleanupSockets()
              trySendBlocking(null)
            }

            awaitClose { stopAdvertising() }
          }
          .flowOn(Dispatchers.IO)

  override fun stopReceivingConnectionRequest() {
    cleanupSockets()
  }

  private fun stopAdvertising() {
    isAdvertising.set(false)
  }

  private fun cleanupSockets() {
    stopAdvertising()

    // Close the server socket to free up the address
    serverSocket.getAndSet(null)?.let { socket ->
      try {
        EchoDebugLogger.debug(TAG, "Closing LocalServerSocket for $socketName")
        socket.close()
      } catch (e: Exception) {
        EchoDebugLogger.warn(TAG, "Error closing LocalServerSocket", e)
      }
    }

    // Close any accepted socket that's still open
    acceptedLocalSocket.getAndSet(null)?.let { socket ->
      try {
        EchoDebugLogger.debug(TAG, "Closing accepted LocalSocket")
        socket.close()
      } catch (e: Exception) {
        EchoDebugLogger.warn(TAG, "Error closing accepted LocalSocket", e)
      }
    }
  }

  /**
   * Provides the accepted [LocalSocket] for tunneling and clears the stored reference. The caller
   * becomes responsible for closing the socket.
   */
  override fun consumeAcceptedLocalSocket(): LocalSocket? {
    return acceptedLocalSocket.getAndSet(null)
  }

  @OptIn(ExperimentalCoroutinesApi::class)
  private suspend fun LocalServerSocket.awaitConnection() =
      suspendCancellableCoroutine<LocalSocket> {
        val closeSocket: (cause: Throwable?) -> Unit = {
          EchoDebugLogger.debug(TAG, "Socket thread cancellation, closing.")
          try {
            close()
          } catch (_: Throwable) {}
        }

        // LocalServerSocket.accept is a blocking call thus we use a thread to be able to interrupt
        // and close
        // the socket when we're done with it.
        thread {
          it.invokeOnCancellation(closeSocket)
          try {
            it.resume(accept(), onCancellation = closeSocket)
          } catch (e: IOException) {
            it.cancel(e)
          }
        }
      }
}
