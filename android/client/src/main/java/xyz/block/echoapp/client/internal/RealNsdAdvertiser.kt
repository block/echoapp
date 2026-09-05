package xyz.block.echoapp.client.internal

import android.content.Context
import android.content.Context.NSD_SERVICE
import android.content.Context.WIFI_SERVICE
import android.net.nsd.NsdManager
import android.net.nsd.NsdManager.PROTOCOL_DNS_SD
import android.net.nsd.NsdManager.RegistrationListener
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.net.wifi.WifiManager.MulticastLock
import xyz.block.echoapp.client.ConnectionRequest
import xyz.block.echoapp.client.EchoClient
import xyz.block.echoapp.client.internal.RealNsdAdvertiser.NsdRegistrationEvent.Failure
import xyz.block.echoapp.client.internal.RealNsdAdvertiser.NsdRegistrationEvent.Success
import xyz.block.echoapp.client.internal.RealNsdAdvertiser.NsdRegistrationEvent.Unregistration
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.suspendCancellableCoroutine

internal class RealNsdAdvertiser(
    private val context: Context,
) : ConnectionHandshaker {
  private val nsdManager: NsdManager by lazy { context.getSystemService(NSD_SERVICE) as NsdManager }
  private val wifiManager: WifiManager? by lazy {
    context.getSystemService(WIFI_SERVICE) as? WifiManager
  }

  private val nsdSocket = AtomicReference<ServerSocket?>(null)
  private val listener = AtomicReference<RegistrationListener?>(null)
  private var multicastLock = AtomicReference<MulticastLock?>(null)

  private lateinit var serviceNameWithDeviceIdentifier: String
  private lateinit var deviceName: String
  private lateinit var appIdentifier: String

  companion object {
    const val TAG = "NsdAdvertiser"
    const val SERVICE_TYPE = "_echoclient._tcp."
    const val SERVICE_PORT = 42633
    const val MULTICAST_LOCK_NAME = "xyz.block.echoapp.client.DNSSD"

    const val EMULATOR_IDENTIFIER = ":android_emulator"

    const val ATTRIBUTE_DEVICE_NAME = "device_name"
    const val ATTRIBUTE_APP_IDENTIFIER = "app_identifier"

    /**
     * This attribute is provided to [NsdServiceInfo] as a workaround for our advertised NsdServer
     * not being resolvable by other clients on the network, i.e. the desktop Echo app on Mac.
     *
     * This workaround was provided by Google
     * [here](https://issuetracker.google.com/issues/350179261#comment13).
     */
    const val DUMMY_ATTRIBUTE_SOURCE = "source"

    private val connectionAdapter = echoMoshi.adapter(ConnectionRequest::class.java)
  }

  private fun registerService(serviceInfo: NsdServiceInfo): Flow<NsdRegistrationEvent> =
      callbackFlow {
        val newListener =
            object : RegistrationListener {
                  override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                    EchoDebugLogger.debug(TAG, "Service has been registered $serviceInfo")
                    acquireMulticastLock()
                    trySendBlocking(Success(serviceInfo))
                  }

                  override fun onRegistrationFailed(
                      serviceInfo: NsdServiceInfo,
                      errorCode: Int,
                  ) {
                    EchoDebugLogger.debug(TAG, "Service registration failed $serviceInfo")
                    trySendBlocking(Failure(errorCode))
                  }

                  override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                    EchoDebugLogger.debug(TAG, "Service has been unregistered $serviceInfo")
                    releaseMulticastLock()
                    trySendBlocking(Unregistration(serviceInfo))
                  }

                  override fun onUnregistrationFailed(
                      serviceInfo: NsdServiceInfo,
                      errorCode: Int,
                  ) {
                    EchoDebugLogger.debug(TAG, "Service un-registration failed $serviceInfo")
                    trySendBlocking(Failure(errorCode))
                  }
                }
                .also { listener.set(it) }

        nsdManager.registerService(serviceInfo, PROTOCOL_DNS_SD, newListener)
        awaitClose { stopAdvertising() }
      }

  override fun attach(client: EchoClient) {
    val deviceIdentifier = client.deviceIdentifierResolver.resolve()
    serviceNameWithDeviceIdentifier =
        if (isDeviceProbablyEmulator()) {
          // Android Emulators require additional information on the identifier for Echo to connect.
          // Due to
          // the sandbox nature of the emulator, host and post information via NSD is not populated
          // giving
          // Echo no way to know how to connect.
          "$deviceIdentifier$EMULATOR_IDENTIFIER"
        } else {
          deviceIdentifier
        }
    deviceName = client.deviceNameResolver.resolve()
    appIdentifier = client.appIdentifier
  }

  override suspend fun startReceivingConnectionRequest(): Flow<ConnectionRequest?> {
    val serviceInfo =
        NsdServiceInfo().apply {
          serviceName = serviceNameWithDeviceIdentifier
          serviceType = SERVICE_TYPE
          port = SERVICE_PORT
          setAttribute(ATTRIBUTE_DEVICE_NAME, deviceName)
          setAttribute(ATTRIBUTE_APP_IDENTIFIER, appIdentifier)
          // https://issuetracker.google.com/issues/350179261#comment13
          setAttribute(DUMMY_ATTRIBUTE_SOURCE, "echo-debugger")
        }

    return registerService(serviceInfo)
        .map {
          val newServerSocket = ServerSocket(SERVICE_PORT).also { nsdSocket.set(it) }
          val socket = newServerSocket.awaitConnection()
          val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
          val data = reader.readLine()

          try {
            connectionAdapter.fromJson(data)
          } catch (e: Exception) {
            EchoDebugLogger.error(TAG, "Error decoding connection request!", e)
            null
          } finally {
            socket.close()
          }
        }
        .flowOn(Dispatchers.IO)
  }

  override fun stopReceivingConnectionRequest() {
    stopAdvertising()
  }

  @Synchronized
  fun stopAdvertising() {
    EchoDebugLogger.debug(TAG, "Stopping advertisement")
    listener.getAndSet(null)?.let { currentListener ->
      nsdManager.unregisterService(currentListener)
    }
    nsdSocket.getAndSet(null)?.close()
  }

  @Synchronized
  fun isAdvertising(): Boolean {
    return listener.get() != null
  }

  @OptIn(ExperimentalCoroutinesApi::class)
  private suspend fun ServerSocket.awaitConnection() =
      suspendCancellableCoroutine<Socket> {
        val closeSocket: (cause: Throwable?) -> Unit = {
          EchoDebugLogger.debug(TAG, "Socket thread cancellation, closing.")
          try {
            close()
          } catch (_: Throwable) {}
        }

        // ServerSocket.accept is a blocking call thus we use a thread to be able to interrupt and
        // close
        // the socket when we're done with it.
        thread {
          it.invokeOnCancellation(closeSocket)
          try {
            it.resume(accept(), onCancellation = closeSocket)
          } catch (e: SocketException) {
            it.cancel(e)
          }
        }
      }

  @Synchronized
  private fun acquireMulticastLock() {
    wifiManager?.createMulticastLock(MULTICAST_LOCK_NAME)?.let { newLock ->
      newLock.setReferenceCounted(true)
      newLock.acquire()
      multicastLock.set(newLock)
    }
        ?: run {
          EchoDebugLogger.wtf(TAG, "Can't get WifiManager, unable to acquire multicast lock.")
        }
  }

  @Synchronized
  private fun releaseMulticastLock() {
    multicastLock.getAndSet(null)?.release()
  }

  sealed interface NsdRegistrationEvent {
    data class Success(val serviceInfo: NsdServiceInfo) : NsdRegistrationEvent

    data class Failure(val errorCode: Int) : NsdRegistrationEvent

    data class Unregistration(val serviceInfo: NsdServiceInfo) : NsdRegistrationEvent
  }
}
