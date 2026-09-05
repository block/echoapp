package xyz.block.echoapp.sample.keyvaluestore

import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate
import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.StringValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueEntry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeImmutableKeyValueStoresProvider : KeyValueStoresProvider {
  override val updates = MutableSharedFlow<KeyValueEntryUpdate>(extraBufferCapacity = 1)

  override fun startObservation(coroutineScope: CoroutineScope) = Unit

  override fun stopObservation() = Unit

  override suspend fun refresh(): List<KeyValueStore> =
      List(4) { storeIndex ->
        KeyValueStore(
            id = "store$storeIndex",
            name = "Store $storeIndex",
            entries =
                List(4) { entryIndex ->
                  KeyValueEntry(
                      key = "entry$entryIndex",
                      value = StringValue("Value $entryIndex"),
                      isEditable = false,
                  )
                },
            lastUpdatedMillis = System.currentTimeMillis(),
            isReadOnly = true,
        )
      }

  override suspend fun addOrUpdateValue(
      store: KeyValueStore,
      key: String,
      value: KeyValue,
  ) = Unit

  override suspend fun deleteKey(
      store: KeyValueStore,
      key: String,
  ) = Unit
}
