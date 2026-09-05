package xyz.block.echoapp.client.internal

import xyz.block.echoapp.client.ConnectionRequest
import xyz.block.echoapp.client.EchoClient
import kotlinx.coroutines.flow.Flow

/** Wrapper around the Android NSD API, used by [EchoClient]. */
interface ConnectionHandshaker {
  /** This is guaranteed to be invoked before [startReceivingConnectionRequest]. */
  fun attach(client: EchoClient)

  /**
   * Returns a [Flow] that while collected advertises the service on the network using Android NSD.
   *
   * @return A flow that emits [ConnectionRequest]s when a client connects to the service. May emit
   *   a null connection request if the request cannot be parsed.
   */
  suspend fun startReceivingConnectionRequest(): Flow<ConnectionRequest?>

  fun stopReceivingConnectionRequest()
}
