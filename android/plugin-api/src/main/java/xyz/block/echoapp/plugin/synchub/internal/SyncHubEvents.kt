package xyz.block.echoapp.plugin.synchub.internal

import xyz.block.echoapp.plugin.synchub.SyncOperationStatus
import xyz.block.echoapp.plugin.synchub.SyncOperationType
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/**
 * Events sent from the mobile SyncHub plugin to the Echo desktop app.
 *
 * This plugin sends minimal structured metadata for filtering/display, plus raw JSON payloads of
 * the sync-hub proto requests and responses. The Echo desktop app parses the raw JSON to extract
 * details for display.
 */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface SyncHubClientEvent {
  /**
   * Reports a sync request being sent.
   *
   * @property requestJson The raw sync-hub request proto serialized as JSON (e.g.,
   *   SyncDomainRequest).
   */
  @Json(name = "sync_request")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class SyncRequest(
      @Json(name = "id") val id: String,
      @Json(name = "domain") val domain: String,
      @Json(name = "timestamp") val timestamp: String,
      @Json(name = "operationType") val operationType: SyncOperationType,
      @Json(name = "requestJson") val requestJson: String,
  ) : SyncHubClientEvent

  /**
   * Reports a sync response received.
   *
   * @property responseJson The raw sync-hub response proto serialized as JSON (e.g.,
   *   SyncDomainResponse).
   */
  @Json(name = "sync_response")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class SyncResponse(
      @Json(name = "requestId") val requestId: String,
      @Json(name = "domain") val domain: String,
      @Json(name = "timestamp") val timestamp: String,
      @Json(name = "operationType") val operationType: SyncOperationType,
      @Json(name = "durationMs") val durationMs: Long,
      @Json(name = "status") val status: SyncOperationStatus,
      @Json(name = "errorMessage") val errorMessage: String,
      @Json(name = "responseJson") val responseJson: String,
  ) : SyncHubClientEvent

  /** Reports the connection status to various hubs. */
  @Json(name = "connection_status")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class ConnectionStatus(
      @Json(name = "domain") val domain: String,
      @Json(name = "timestamp") val timestamp: String,
      @Json(name = "isConnectedToLocalHub") val isConnectedToLocalHub: Boolean,
      @Json(name = "isConnectedToCloudHub") val isConnectedToCloudHub: Boolean,
  ) : SyncHubClientEvent

  /** Reports outbox state for a domain. */
  @Json(name = "outbox_status")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class OutboxStatus(
      @Json(name = "domain") val domain: String,
      @Json(name = "timestamp") val timestamp: String,
      @Json(name = "pendingCommitCount") val pendingCommitCount: Int,
  ) : SyncHubClientEvent
}

/** Events sent from the Echo desktop app to the mobile SyncHub plugin. */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface SyncHubDesktopEvent {
  /** Request to trigger a manual sync for a domain. */
  @Json(name = "trigger_sync")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class TriggerSync(
      @Json(name = "domain") val domain: String,
  ) : SyncHubDesktopEvent

  /** Request to clear plugin data display. */
  @Json(name = "clear_data") data object ClearData : SyncHubDesktopEvent
}
