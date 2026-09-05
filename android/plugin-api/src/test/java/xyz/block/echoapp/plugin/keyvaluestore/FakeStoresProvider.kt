package xyz.block.echoapp.plugin.keyvaluestore

import app.cash.turbine.Turbine
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate
import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.rules.ExternalResource

class FakeStoresProviderRule(
    val provider: FakeStoresProvider = FakeStoresProvider(),
) : ExternalResource() {
  override fun after() =
      with(provider) {
        val failures =
            listOf(
                    addOrUpdateCalls,
                    deleteCalls,
                    nextRefreshResult,
                )
                .mapNotNull { turbine ->
                  runCatching { turbine.ensureAllEventsConsumed() }.exceptionOrNull()?.message
                }
        check(failures.isEmpty()) {
          "Unconsumed events found -> ${failures.joinToString(separator = "\n")}"
        }
      }
}

class FakeStoresProvider : KeyValueStoresProvider {
  val addOrUpdateCalls = Turbine<AddOrUpdateCall>(name = "addOrUpdateCalls")
  var nextAddOrUpdateError: Throwable? = null
  val deleteCalls = Turbine<DeleteCall>(name = "deleteCalls")
  var nextDeleteError: Throwable? = null
  val nextRefreshResult = Turbine<List<KeyValueStore>>(name = "nextRefreshResult")

  override val updates =
      MutableSharedFlow<KeyValueEntryUpdate>(
          extraBufferCapacity = 1,
          replay = 1,
      )

  override fun startObservation(coroutineScope: CoroutineScope) = Unit

  override fun stopObservation() = Unit

  override suspend fun refresh(): List<KeyValueStore> = nextRefreshResult.awaitItem()

  override suspend fun addOrUpdateValue(
      store: KeyValueStore,
      key: String,
      value: KeyValue,
  ) {
    nextAddOrUpdateError?.let {
      nextAddOrUpdateError = null
      throw it
    }
    addOrUpdateCalls.add(AddOrUpdateCall(store.id, key, value))
  }

  override suspend fun deleteKey(
      store: KeyValueStore,
      key: String,
  ) {
    nextDeleteError?.let {
      nextDeleteError = null
      throw it
    }
    deleteCalls.add(DeleteCall(store.id, key))
  }

  data class AddOrUpdateCall(
      val storeId: String,
      val key: String,
      val value: KeyValue,
  )

  data class DeleteCall(
      val storeId: String,
      val key: String,
  )
}
