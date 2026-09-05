package xyz.block.echoapp.plugin.synchub

import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.buffered.BufferedClientPlugin
import xyz.block.echoapp.plugin.buffered.send
import xyz.block.echoapp.plugin.collectIn
import xyz.block.echoapp.plugin.collectLatestIn
import xyz.block.echoapp.plugin.onEventReceived
import xyz.block.echoapp.plugin.synchub.internal.SyncHubClientEvent
import xyz.block.echoapp.plugin.synchub.internal.SyncHubClientEvent.ConnectionStatus
import xyz.block.echoapp.plugin.synchub.internal.SyncHubClientEvent.OutboxStatus
import xyz.block.echoapp.plugin.synchub.internal.SyncHubClientEvent.SyncRequest
import xyz.block.echoapp.plugin.synchub.internal.SyncHubClientEvent.SyncResponse
import xyz.block.echoapp.plugin.synchub.internal.SyncHubDesktopEvent
import xyz.block.echoapp.plugin.utils.logDebug
import xyz.block.echoapp.plugin.utils.logError
import java.util.UUID
import kotlinx.coroutines.CoroutineScope

/**
 * Echo plugin for monitoring Sync Hub operations and state.
 *
 * This plugin sends minimal structured metadata for filtering/display, plus raw JSON payloads of
 * the sync-hub proto requests and responses. The Echo desktop app parses the raw JSON to extract
 * and display details.
 *
 * Usage:
 * ```kotlin
 * val syncHubPlugin = SyncHubPlugin(
 *   currentTimestampProvider = { dateFormat.format(Date()) },
 * )
 *
 * // Report a sync request (pass the raw proto as JSON)
 * val requestId = syncHubPlugin.reportSyncRequest(
 *   domain = "kds",
 *   operationType = SyncOperationType.SYNC_DOMAIN,
 *   requestJson = moshi.adapter(SyncDomainRequest::class.java).toJson(request),
 * )
 *
 * // Report the response (pass the raw proto as JSON)
 * syncHubPlugin.reportSyncResponse(
 *   requestId = requestId,
 *   domain = "kds",
 *   operationType = SyncOperationType.SYNC_DOMAIN,
 *   durationMs = 250,
 *   responseJson = moshi.adapter(SyncDomainResponse::class.java).toJson(response),
 * )
 * ```
 */
open class SyncHubPlugin(
    bufferSize: Int = DEFAULT_BUFFER_SIZE,
    private val currentTimestampProvider: () -> String,
    private val uuidProvider: () -> String = { UUID.randomUUID().toString() },
) : BufferedClientPlugin(bufferSize = bufferSize) {
  override val pluginIdentifier: String = "com.echo.plugin.synchub"

  private var onTriggerSync: ((domain: String) -> Unit)? = null

  override fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  ) {
    super.onConnect(scope, connection)

    connection.onEventReceived<SyncHubDesktopEvent>().collectIn(scope) { event ->
      try {
        handleDesktopEvent(event)
      } catch (e: Exception) {
        logError("Failed to handle SyncHub desktop event", e)
      }
    }

    connection.isDesktopPluginActive.collectLatestIn(scope) { isActive ->
      logDebug("SyncHub plugin active: $isActive")
    }
  }

  /** Register a callback for when the desktop requests a manual sync. */
  fun setOnTriggerSync(callback: (domain: String) -> Unit) {
    onTriggerSync = callback
  }

  /**
   * Report a sync request. Returns a request ID to use when reporting the response.
   *
   * @param requestJson The raw sync-hub request proto serialized as JSON.
   */
  suspend fun reportSyncRequest(
      domain: String,
      operationType: SyncOperationType,
      requestJson: String,
  ): String {
    val requestId = uuidProvider()
    send<SyncHubClientEvent>(
        SyncRequest(
            id = requestId,
            domain = domain,
            timestamp = currentTimestampProvider(),
            operationType = operationType,
            requestJson = requestJson,
        ),
    )
    return requestId
  }

  /**
   * Report a successful sync response.
   *
   * @param responseJson The raw sync-hub response proto serialized as JSON.
   */
  suspend fun reportSyncResponse(
      requestId: String,
      domain: String,
      operationType: SyncOperationType,
      durationMs: Long,
      responseJson: String,
  ) {
    send<SyncHubClientEvent>(
        SyncResponse(
            requestId = requestId,
            domain = domain,
            timestamp = currentTimestampProvider(),
            operationType = operationType,
            durationMs = durationMs,
            status = SyncOperationStatus.SUCCESS,
            errorMessage = "",
            responseJson = responseJson,
        ),
    )
  }

  /** Report a failed sync operation. */
  suspend fun reportSyncError(
      requestId: String,
      domain: String,
      operationType: SyncOperationType,
      durationMs: Long,
      errorMessage: String,
  ) {
    send<SyncHubClientEvent>(
        SyncResponse(
            requestId = requestId,
            domain = domain,
            timestamp = currentTimestampProvider(),
            operationType = operationType,
            durationMs = durationMs,
            status = SyncOperationStatus.ERROR,
            errorMessage = errorMessage,
            responseJson = "",
        ),
    )
  }

  /** Report the current connection status to hubs for a domain. */
  suspend fun reportConnectionStatus(
      domain: String,
      isConnectedToLocalHub: Boolean,
      isConnectedToCloudHub: Boolean = false,
  ) {
    send<SyncHubClientEvent>(
        ConnectionStatus(
            domain = domain,
            timestamp = currentTimestampProvider(),
            isConnectedToLocalHub = isConnectedToLocalHub,
            isConnectedToCloudHub = isConnectedToCloudHub,
        ),
    )
  }

  /** Report the current outbox state for a domain. */
  suspend fun reportOutboxStatus(
      domain: String,
      pendingCommitCount: Int,
  ) {
    send<SyncHubClientEvent>(
        OutboxStatus(
            domain = domain,
            timestamp = currentTimestampProvider(),
            pendingCommitCount = pendingCommitCount,
        ),
    )
  }

  private fun handleDesktopEvent(event: SyncHubDesktopEvent) {
    when (event) {
      is SyncHubDesktopEvent.TriggerSync -> {
        logDebug("Desktop requested sync for domain: ${event.domain}")
        onTriggerSync?.invoke(event.domain)
      }
      is SyncHubDesktopEvent.ClearData -> {
        logDebug("Desktop requested data clear")
      }
    }
  }

  private companion object {
    const val DEFAULT_BUFFER_SIZE = 256
  }
}
