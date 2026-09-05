package xyz.block.echoapp.plugin.keyvaluestore

import androidx.annotation.VisibleForTesting
import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.collectIn
import xyz.block.echoapp.plugin.collectLatestIn
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreClientEvent
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreClientEvent.ChangeConfirmation
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreClientEvent.Error
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreClientEvent.UpdateSnapshot
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreDesktopEvent
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreDesktopEvent.AddKey
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreDesktopEvent.DeleteKey
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreDesktopEvent.RequestFullRefresh
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreDesktopEvent.RequestSnapshot
import xyz.block.echoapp.plugin.keyvaluestore.internal.events.KeyValueStoreDesktopEvent.UpdateValue
import xyz.block.echoapp.plugin.keyvaluestore.internal.stores.KeyValueStoreSnapshot
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate.Operation.EntriesCleared
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate.Operation.EntryAddedOrUpdated
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate.Operation.EntryDeleted
import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import xyz.block.echoapp.plugin.keyvaluestore.stores.addOrUpdateEntry
import xyz.block.echoapp.plugin.keyvaluestore.stores.clearEntries
import xyz.block.echoapp.plugin.keyvaluestore.stores.removeEntry
import xyz.block.echoapp.plugin.keyvaluestore.stores.withUpdatedStore
import xyz.block.echoapp.plugin.onEventReceived
import xyz.block.echoapp.plugin.send
import xyz.block.echoapp.plugin.utils.logDebug
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.coroutineContext
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flattenMerge
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** A plugin for viewing & editing key-value stores like `SharedPreferences`. */
@OptIn(ExperimentalStdlibApi::class, ExperimentalCoroutinesApi::class)
open class KeyValueStorePlugin(
    private val timestampProvider: () -> Long = { System.currentTimeMillis() },
    private val storesProviders: List<KeyValueStoresProvider>,
) : ClientPlugin {
  override val pluginIdentifier: String = "com.echo.plugin.keyvaluestore"

  // Storage & caching
  @VisibleForTesting
  internal val stores =
      AtomicReference(
          mutableMapOf<KeyValueStoresProvider, List<KeyValueStore>>(),
      )

  // Connection & queuing
  private val requestSendSnapshotQueue = MutableSharedFlow<SendSnapshotQueueRequest>(replay = 1)

  @OptIn(FlowPreview::class)
  override fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  ) {
    scope.launch { connection.sendSnapshot(shouldRefresh = true) }

    connection.isDesktopPluginActive
        .onEach { isActive -> sendSnapshotDebounced(shouldRefresh = true) }
        .flatMapLatest { isActive ->
          if (isActive) {
            storesProviders.forEach { it.startObservation(scope) }
            logDebug("Observation job running…")
            observeProviderUpdates()
          } else {
            storesProviders.forEach { it.stopObservation() }
            logDebug("Observation job stopped.")
            emptyFlow()
          }
        }
        .collectLatestIn(scope) { (provider, update) ->
          logDebug("Got update from provider ${provider::class.java.name}: $update")
          stores.updateAndGet { current ->
            current.apply { this[provider] = this[provider]?.applyUpdate(update).orEmpty() }
          }
          sendSnapshotDebounced(shouldRefresh = false)
        }

    requestSendSnapshotQueue
        .onStart { logDebug("Snapshot queue job running…") }
        .debounce(500.milliseconds)
        .collectLatestIn(scope) { request ->
          connection.sendSnapshot(shouldRefresh = request.shouldRefresh)
        }

    connection.onEventReceived<KeyValueStoreDesktopEvent>().collectIn(scope) { event ->
      connection.handleDesktopEvent(event)
    }
  }

  @OptIn(FlowPreview::class)
  private fun observeProviderUpdates(): Flow<Pair<KeyValueStoresProvider, KeyValueEntryUpdate>> {
    return storesProviders
        .asFlow()
        .map { provider -> provider.updates.map { provider to it } }
        .flattenMerge()
  }

  private suspend fun refreshStores() {
    logDebug("Refreshing stores…")
    stores.set(storesProviders.associateWith { it.refresh() }.toMutableMap())
  }

  private suspend fun PluginConnection.sendSnapshot(shouldRefresh: Boolean) {
    if (shouldRefresh) refreshStores()
    if (!coroutineContext.isActive) return
    logDebug("Sending snapshot…")
    sendClientEvent(
        UpdateSnapshot(
            snapshot =
                KeyValueStoreSnapshot(
                    stores = stores.get().flatMap { (_, stores) -> stores },
                    timestampMillis = timestampProvider(),
                ),
        ),
    )
  }

  private suspend fun sendSnapshotDebounced(shouldRefresh: Boolean) {
    requestSendSnapshotQueue.emit(SendSnapshotQueueRequest(shouldRefresh = shouldRefresh))
  }

  private fun List<KeyValueStore>.applyUpdate(update: KeyValueEntryUpdate): List<KeyValueStore> {
    return withUpdatedStore(name = update.storeName) {
      when (val operation = update.operation) {
        is EntryAddedOrUpdated ->
            addOrUpdateEntry(key = operation.key) {
              copy(
                  value = operation.value,
                  type = operation.value.type,
                  lastModifiedMillis = timestampProvider(),
              )
            }

        is EntryDeleted -> removeEntry(key = operation.key)
        EntriesCleared -> clearEntries()
      }
    }
  }

  private suspend fun PluginConnection.handleDesktopEvent(event: KeyValueStoreDesktopEvent) {
    logDebug("Received desktop event: $event")
    when (event) {
      RequestSnapshot -> sendSnapshotDebounced(shouldRefresh = false)
      RequestFullRefresh -> sendSnapshotDebounced(shouldRefresh = true)
      is UpdateValue -> handleConflictAwareUpdate(event)
      is AddKey -> handleConflictAwareAdd(event)
      is DeleteKey -> handleConflictAwareDelete(event)
    }
  }

  private suspend fun PluginConnection.handleConflictAwareUpdate(event: UpdateValue) {
    val key = event.key
    val storeId = event.storeId
    val changeId = event.changeId

    val (provider, store) = findProviderAndStoreByStoreId(storeId)
    if (provider == null || store == null) {
      sendClientEvent(Error(storeId = storeId, message = "Unknown store ID: $storeId"))
      return
    }
    try {
      provider.addOrUpdateValue(
          store = store,
          key = key,
          value = event.newValue,
      )
      sendChangeConfirmation(
          storeId = storeId,
          changeId = changeId,
          success = true,
      )
    } catch (t: Throwable) {
      sendChangeConfirmation(
          storeId = storeId,
          changeId = changeId,
          success = false,
          error = "Failed to update $key: ${t.message}",
      )
    }
  }

  private suspend fun PluginConnection.handleConflictAwareAdd(event: AddKey) {
    val key = event.key
    val storeId = event.storeId
    val changeId = event.changeId

    val (provider, store) = findProviderAndStoreByStoreId(storeId)
    if (provider == null || store == null) {
      sendClientEvent(Error(storeId = storeId, message = "Unknown store ID: $storeId"))
      return
    }
    try {
      provider.addOrUpdateValue(
          store = store,
          key = key,
          value = event.value,
      )
      sendChangeConfirmation(
          storeId = storeId,
          changeId = changeId,
          success = true,
      )
    } catch (t: Throwable) {
      sendChangeConfirmation(
          storeId = storeId,
          changeId = changeId,
          success = false,
          error = "Failed to add $key: ${t.message}",
      )
    }
  }

  private suspend fun PluginConnection.handleConflictAwareDelete(event: DeleteKey) {
    val key = event.key
    val storeId = event.storeId
    val changeId = event.changeId

    val (provider, store) = findProviderAndStoreByStoreId(storeId)
    if (provider == null || store == null) {
      sendClientEvent(Error(storeId = storeId, message = "Unknown store ID: $storeId"))
      return
    }
    try {
      provider.deleteKey(
          store = store,
          key = key,
      )
      sendChangeConfirmation(
          storeId = storeId,
          changeId = changeId,
          success = true,
      )
    } catch (t: Throwable) {
      sendChangeConfirmation(
          storeId = storeId,
          changeId = changeId,
          success = false,
          error = "Failed to delete $key: ${t.message}",
      )
    }
  }

  private fun findProviderAndStoreByStoreId(
      storeId: String,
  ): Pair<KeyValueStoresProvider?, KeyValueStore?> {
    return stores.get().entries.firstNotNullOfOrNull { (provider, stores) ->
      stores.find { it.id == storeId }?.let { store -> provider to store }
    } ?: (null to null)
  }

  private fun PluginConnection.sendChangeConfirmation(
      storeId: String,
      changeId: String,
      success: Boolean,
      error: String? = null,
  ) {
    sendClientEvent(
        ChangeConfirmation(
            changeId = changeId,
            timestampMillis = timestampProvider(),
            success = success,
        ),
    )
    error?.let {
      sendClientEvent(
          Error(
              storeId = storeId,
              message = error,
          ),
      )
    }
  }

  private fun PluginConnection.sendClientEvent(event: KeyValueStoreClientEvent) {
    send<KeyValueStoreClientEvent>(event)
  }

  private data class SendSnapshotQueueRequest(val shouldRefresh: Boolean)
}
