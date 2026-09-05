package xyz.block.echoapp.plugin.keyvaluestore.providers

import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharedFlow

/**
 * Represents a provider for a certain class of [KeyValueStore]s. For an example, we have one
 * provider for all shared preferences in an app.
 */
interface KeyValueStoresProvider {
  /** Emits updates to entries in the [KeyValueStore]s of this provider. */
  val updates: SharedFlow<KeyValueEntryUpdate>

  /** Informs the provider that it may start observing changes to the [KeyValueStore]s. */
  fun startObservation(coroutineScope: CoroutineScope)

  /** Informs the provider that it must stop observing changes to the [KeyValueStore]s. */
  fun stopObservation()

  /** Forces an immediate refresh of the [KeyValueStore]s in this provider. */
  suspend fun refresh(): List<KeyValueStore>

  /**
   * Adds or updates the [value] of an entry in the given [store] by its [key].
   *
   * Implementations may throw an exception to communicate an error to the desktop client.
   */
  @Throws(Exception::class)
  suspend fun addOrUpdateValue(
      store: KeyValueStore,
      key: String,
      value: KeyValue,
  )

  /**
   * Deletes an entry from the given [store] by its [key], if it exists.
   *
   * Implementations may throw an exception to communicate an error to the desktop client.
   */
  @Throws(Exception::class)
  suspend fun deleteKey(
      store: KeyValueStore,
      key: String,
  )

  /** Describes individual store updates emitted by a provider. */
  data class KeyValueEntryUpdate(
      val storeName: String,
      val operation: Operation,
  ) {
    sealed interface Operation {
      data class EntryAddedOrUpdated(
          val key: String,
          val value: KeyValue,
      ) : Operation

      data class EntryDeleted(val key: String) : Operation

      data object EntriesCleared : Operation
    }
  }
}
