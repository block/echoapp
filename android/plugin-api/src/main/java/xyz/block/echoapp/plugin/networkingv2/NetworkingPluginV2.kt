package xyz.block.echoapp.plugin.networkingv2

import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.collectIn
import xyz.block.echoapp.plugin.networkingv2.internal.Error
import xyz.block.echoapp.plugin.networkingv2.internal.HumanReadableResponse
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginClientEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginClientEvent.FinalizedResponseEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginServerEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginServerEvent.ProposedHumanReadableResponseEvent
import xyz.block.echoapp.plugin.networkingv2.internal.NetworkingPluginServerEvent.RawResponseEvent
import xyz.block.echoapp.plugin.networkingv2.internal.Request
import xyz.block.echoapp.plugin.networkingv2.internal.Response
import xyz.block.echoapp.plugin.onEventReceived
import xyz.block.echoapp.plugin.send
import xyz.block.echoapp.plugin.utils.logDebug
import xyz.block.echoapp.plugin.utils.logError
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableJob
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * Echo networking plugin that supports proxying requests through Echo. Implements ClientPlugin to
 * provide bi-directional communication.
 *
 * TODO: Write unit tests.
 */
@OptIn(ExperimentalStdlibApi::class)
open class NetworkingPluginV2(
    outboundBufferSize: Int = DEFAULT_OUTBOUND_BUFFER_SIZE,
) : ClientPlugin {
  override val pluginIdentifier = "com.echo.plugin.network"

  private val responseJobs = ConcurrentHashMap<String, CompletableJob>()
  private val responses = ConcurrentHashMap<String, Response<*>>()
  private val outboundEvents =
      MutableSharedFlow<NetworkingPluginClientEvent>(extraBufferCapacity = outboundBufferSize)

  internal var isPluginConnected: Boolean = false
    private set

  override fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  ) {
    isPluginConnected = true

    connection.onEventReceived<NetworkingPluginServerEvent>().collectIn(scope) { event ->
      try {
        logDebug("Handling desktop event: $event")
        handleServerEvent(event)
      } catch (e: Exception) {
        logError("Failed to handle data from Echo: ", e)
      }
    }

    outboundEvents.collectIn(scope) { connection.send<NetworkingPluginClientEvent>(it) }
  }

  override suspend fun onDisconnect() {
    isPluginConnected = false
  }

  /** Record a request in passive mode (same as original NetworkingPlugin) */
  fun recordRequest(request: Request) {
    val event = NetworkingPluginClientEvent.RequestEvent(request, proxy = false)
    sendClientEvent(event)
  }

  /** Proxy a request through Echo */
  suspend fun proxy(request: Request): Response<*> {
    val event = NetworkingPluginClientEvent.RequestEvent(request, proxy = true)
    sendClientEvent(event)

    return waitForResponse(request.id)
  }

  suspend fun waitForResponse(requestId: String): Response<*> {
    return Job().let {
      responseJobs[requestId] = it
      it.join()
      responses.remove(requestId) ?: error("Cannot find response matching $requestId")
    }
  }

  /** Finalize a response to complete the interaction */
  fun finalizeResponse(response: HumanReadableResponse) {
    val event = FinalizedResponseEvent(response)
    sendClientEvent(event)
  }

  /** Report an error during request processing */
  fun reportError(
      error: Error,
      requestID: String,
  ) {
    val event = NetworkingPluginClientEvent.ErrorEvent(error, requestID)
    sendClientEvent(event)
  }

  private fun handleServerEvent(event: NetworkingPluginServerEvent) {
    when (event) {
      is RawResponseEvent -> {
        val requestId = event.response.requestID
        responseJobs.remove(requestId)?.let {
          responses[requestId] = event.response
          it.complete()
        } ?: error("No matching request found for $requestId")
      }

      is ProposedHumanReadableResponseEvent -> {
        val requestId = event.response.requestID
        responseJobs.remove(requestId)?.let {
          responses[requestId] = event.response
          it.complete()
        } ?: error("No matching request found for $requestId")
      }
    }
  }

  private fun sendClientEvent(event: NetworkingPluginClientEvent): Boolean {
    return outboundEvents.tryEmit(event).also {
      if (!it) logDebug("Failed to send client event: $event")
    }
  }

  private companion object {
    const val DEFAULT_OUTBOUND_BUFFER_SIZE = 128
  }
}
