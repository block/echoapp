package xyz.block.echoapp.plugin.keyvaluestore

import app.cash.turbine.plusAssign
import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.keyvaluestore.FakeStoresProvider.AddOrUpdateCall
import xyz.block.echoapp.plugin.keyvaluestore.FakeStoresProvider.DeleteCall
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate.Operation.EntryAddedOrUpdated
import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.BooleanValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.Int32Value
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.StringValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueEntry
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class KeyValueStorePluginTest {
  private val fakeCurrentTimestamp = 1_000_000_000L
  private val fakeStore =
      KeyValueStore(
          id = "store-id",
          name = "fake-store",
          entries =
              listOf(
                  KeyValueEntry(
                      key = "fake-string",
                      value = StringValue("hello, world"),
                      isEditable = true,
                  ),
                  KeyValueEntry(
                      key = "fake-number",
                      value = Int32Value(42),
                      isEditable = true,
                  ),
              ),
          lastUpdatedMillis = fakeCurrentTimestamp,
      )

  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val fakeStoresProviderRule = FakeStoresProviderRule()
  private val fakeStoresProvider = fakeStoresProviderRule.provider

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val plugin =
      KeyValueStorePlugin(
          timestampProvider = { fakeCurrentTimestamp },
          storesProviders = listOf(fakeStoresProviderRule.provider),
      )

  @Test
  fun `plugin has expected ID`() {
    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.keyvaluestore")
  }

  @Test
  fun `plugin refreshes stores and sends snapshot on connection`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(listOf(fakeStore))
    plugin.onConnect(backgroundScope, pluginConnection)

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"updateSnapshot\":{\"_0\":{\"stores\":[{\"id\":\"store-id\",\"name\":\"fake-store\"," +
                "\"entries\":[{\"key\":\"fake-string\",\"value\":{\"string\":{\"_0\":\"hello, world\"}}," +
                "\"isEditable\":true,\"modificationHistory\":[],\"type\":\"string\"}," +
                "{\"key\":\"fake-number\",\"value\":{\"integer\":{\"_0\":42}},\"isEditable\":true," +
                "\"modificationHistory\":[],\"type\":\"integer\"}],\"lastUpdated\":1000000000," +
                "\"sfSymbol\":\"gearshape.fill\",\"isReadOnly\":false,\"supportedTypes\":[" +
                "\"array\",\"data\",\"boolean\",\"date\",\"float\",\"double\",\"integer16\",\"integer\"," +
                "\"integer64\",\"dictionary\",\"string\",\"url\",\"unknown\"]" +
                "}],\"timestamp\":1000000000}}}",
        )

    backgroundScope.cancel()
  }

  @Test
  fun `sends debounced snapshot onDesktopPluginActive`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    fakeStoresProvider.nextRefreshResult.add(listOf(fakeStore))
    pluginConnection.isDesktopPluginActive.value = true
    runCurrent()
    pluginConnection.expectNoSentData()

    advanceTimeBy(501.milliseconds)
    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"updateSnapshot\":{\"_0\":{\"stores\":[{\"id\":\"store-id\",\"name\":\"fake-store\"," +
                "\"entries\":[{\"key\":\"fake-string\",\"value\":{\"string\":{\"_0\":\"hello, world\"}}," +
                "\"isEditable\":true,\"modificationHistory\":[],\"type\":\"string\"}," +
                "{\"key\":\"fake-number\",\"value\":{\"integer\":{\"_0\":42}},\"isEditable\":true," +
                "\"modificationHistory\":[],\"type\":\"integer\"}],\"lastUpdated\":1000000000," +
                "\"sfSymbol\":\"gearshape.fill\",\"isReadOnly\":false,\"supportedTypes\":[" +
                "\"array\",\"data\",\"boolean\",\"date\",\"float\",\"double\",\"integer16\",\"integer\"," +
                "\"integer64\",\"dictionary\",\"string\",\"url\",\"unknown\"]" +
                "}],\"timestamp\":1000000000}}}",
        )
  }

  @Test
  fun `handles request snapshot desktop event by sending current snapshot`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    pluginConnection.receivedData += "{\"requestSnapshot\":{}}"
    runCurrent()
    pluginConnection.expectNoSentData()

    advanceTimeBy(501.milliseconds)
    // Request snapshot doesn't trigger a refresh!
    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"updateSnapshot\":{\"_0\":{\"stores\":[],\"timestamp\":$fakeCurrentTimestamp}}}",
        )
  }

  @Test
  fun `handles request full refresh desktop event by refreshing and sending snapshot`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    fakeStoresProvider.nextRefreshResult.add(listOf(fakeStore))
    pluginConnection.receivedData += "{\"requestFullRefresh\":{}}"
    runCurrent()
    pluginConnection.expectNoSentData()

    advanceTimeBy(501.milliseconds)
    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"updateSnapshot\":{\"_0\":{\"stores\":[{\"id\":\"store-id\",\"name\":\"fake-store\"," +
                "\"entries\":[{\"key\":\"fake-string\",\"value\":{\"string\":{\"_0\":\"hello, world\"}}," +
                "\"isEditable\":true,\"modificationHistory\":[],\"type\":\"string\"}," +
                "{\"key\":\"fake-number\",\"value\":{\"integer\":{\"_0\":42}},\"isEditable\":true," +
                "\"modificationHistory\":[],\"type\":\"integer\"}],\"lastUpdated\":1000000000," +
                "\"sfSymbol\":\"gearshape.fill\",\"isReadOnly\":false,\"supportedTypes\":[" +
                "\"array\",\"data\",\"boolean\",\"date\",\"float\",\"double\",\"integer16\",\"integer\"," +
                "\"integer64\",\"dictionary\",\"string\",\"url\",\"unknown\"]" +
                "}],\"timestamp\":1000000000}}}",
        )
  }

  @Test
  fun `handles update value desktop event by updating entry in the store`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"updateValue\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"${fakeStore.id}\"," +
            "\"key\": \"fake-string\"," +
            "\"newValue\": {\"string\": {\"_0\": \"updated-value\"}}," +
            "\"type\": \"string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"changeConfirmation\":{\"changeId\":\"fake-change-id\"," +
                "\"timestamp\":$fakeCurrentTimestamp,\"success\":true}}",
        )
    assertThat(fakeStoresProvider.addOrUpdateCalls.awaitItem())
        .isEqualTo(
            AddOrUpdateCall(
                storeId = fakeStore.id,
                key = "fake-string",
                value = StringValue("updated-value"),
            ),
        )
  }

  @Test
  fun `handles update value desktop event for unknown store by sending back error`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"updateValue\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"unknown-store-id\"," +
            "\"key\": \"fake-string\"," +
            "\"newValue\": {\"string\": {\"_0\": \"updated-value\"}}," +
            "\"type\": \"string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"error\":{\"storeId\":\"unknown-store-id\"," +
                "\"message\":\"Unknown store ID: unknown-store-id\"}}",
        )
  }

  @Test
  fun `handles update value desktop event for unknown entry key by appending the entry`() =
      runTest {
        fakeStoresProvider.nextRefreshResult.add(emptyList())
        plugin.onConnect(backgroundScope, pluginConnection)
        pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

        plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
        pluginConnection.receivedData +=
            "{\"updateValue\":{" +
                "\"changeId\": \"fake-change-id\"," +
                "\"storeId\": \"${fakeStore.id}\"," +
                "\"key\": \"unknown-new-boolean\"," +
                "\"newValue\": {\"boolean\": {\"_0\": true}}," +
                "\"type\": \"boolean\"," +
                "\"timestamp\": $fakeCurrentTimestamp" +
                "}}"

        assertThat(pluginConnection.awaitSentData())
            .isEqualTo(
                "{\"changeConfirmation\":{\"changeId\":" +
                    "\"fake-change-id\",\"timestamp\":$fakeCurrentTimestamp,\"success\":true}}",
            )
        assertThat(fakeStoresProvider.addOrUpdateCalls.awaitItem())
            .isEqualTo(
                AddOrUpdateCall(
                    storeId = fakeStore.id,
                    key = "unknown-new-boolean",
                    value = BooleanValue(true),
                ),
            )
      }

  @Test
  fun `handles update value desktop event that triggers an error by sending back an error`() =
      runTest {
        fakeStoresProvider.nextRefreshResult.add(emptyList())
        plugin.onConnect(backgroundScope, pluginConnection)
        pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

        fakeStoresProvider.nextAddOrUpdateError = Exception("Some error occurred!")
        plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
        pluginConnection.receivedData +=
            "{\"updateValue\":{" +
                "\"changeId\": \"fake-change-id\"," +
                "\"storeId\": \"${fakeStore.id}\"," +
                "\"key\": \"fake-string\"," +
                "\"newValue\": {\"string\": {\"_0\": \"updated-value\"}}," +
                "\"type\": \"string\"," +
                "\"timestamp\": $fakeCurrentTimestamp" +
                "}}"

        assertThat(pluginConnection.awaitSentData())
            .isEqualTo(
                "{\"changeConfirmation\":{\"changeId\":\"fake-change-id\"," +
                    "\"timestamp\":1000000000,\"success\":false}}",
            )
        assertThat(pluginConnection.awaitSentData())
            .isEqualTo(
                "{\"error\":{\"storeId\":\"store-id\",\"message\":" +
                    "\"Failed to update fake-string: Some error occurred!\"}}",
            )
      }

  @Test
  fun `handles add key desktop event by updating entry in the store`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"addKey\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"${fakeStore.id}\"," +
            "\"key\": \"fake-string\"," +
            "\"value\": {\"string\": {\"_0\": \"new-value\"}}," +
            "\"type\": \"string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"changeConfirmation\":{\"changeId\":\"fake-change-id\"," +
                "\"timestamp\":$fakeCurrentTimestamp,\"success\":true}}",
        )
    assertThat(fakeStoresProvider.addOrUpdateCalls.awaitItem())
        .isEqualTo(
            AddOrUpdateCall(
                storeId = fakeStore.id,
                key = "fake-string",
                value = StringValue("new-value"),
            ),
        )
  }

  @Test
  fun `handles add key desktop event for unknown store by sending back error`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"addKey\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"unknown-store-id\"," +
            "\"key\": \"fake-string\"," +
            "\"value\": {\"string\": {\"_0\": \"new-value\"}}," +
            "\"type\": \"string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"error\":{\"storeId\":\"unknown-store-id\"," +
                "\"message\":\"Unknown store ID: unknown-store-id\"}}",
        )
  }

  @Test
  fun `handles add key desktop event that triggers an error by sending back an error`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    fakeStoresProvider.nextAddOrUpdateError = Exception("Some error occurred!")
    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"addKey\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"${fakeStore.id}\"," +
            "\"key\": \"fake-string\"," +
            "\"value\": {\"string\": {\"_0\": \"new-value\"}}," +
            "\"type\": \"string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"changeConfirmation\":{\"changeId\":\"fake-change-id\"," +
                "\"timestamp\":1000000000,\"success\":false}}",
        )
    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"error\":{\"storeId\":\"store-id\",\"message\":" +
                "\"Failed to add fake-string: Some error occurred!\"}}",
        )
  }

  @Test
  fun `handles delete key desktop event by removing entry from the store`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"deleteKey\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"${fakeStore.id}\"," +
            "\"key\": \"fake-string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"changeConfirmation\":{\"changeId\":\"fake-change-id\"," +
                "\"timestamp\":$fakeCurrentTimestamp,\"success\":true}}",
        )
    assertThat(fakeStoresProvider.deleteCalls.awaitItem())
        .isEqualTo(
            DeleteCall(
                storeId = fakeStore.id,
                key = "fake-string",
            ),
        )
  }

  @Test
  fun `handles delete key desktop event for unknown store by sending back error`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"deleteKey\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"unknown-store-id\"," +
            "\"key\": \"fake-string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"error\":{\"storeId\":\"unknown-store-id\"," +
                "\"message\":\"Unknown store ID: unknown-store-id\"}}",
        )
  }

  @Test
  fun `handles delete key desktop event that triggers an error by sending back error`() = runTest {
    fakeStoresProvider.nextRefreshResult.add(emptyList())
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

    fakeStoresProvider.nextDeleteError = Exception("Some error occurred!")
    plugin.stores.set(mutableMapOf(fakeStoresProvider to listOf(fakeStore)))
    pluginConnection.receivedData +=
        "{\"deleteKey\":{" +
            "\"changeId\": \"fake-change-id\"," +
            "\"storeId\": \"${fakeStore.id}\"," +
            "\"key\": \"fake-string\"," +
            "\"timestamp\": $fakeCurrentTimestamp" +
            "}}"

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"changeConfirmation\":{\"changeId\":\"fake-change-id\"," +
                "\"timestamp\":1000000000,\"success\":false}}",
        )
    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"error\":{\"storeId\":\"store-id\",\"message\":" +
                "\"Failed to delete fake-string: Some error occurred!\"}}",
        )
  }

  @Test
  fun `handles update operation from provider with unknown entry key by appending entry to store`() =
      runTest {
        val storeWithNoEntries = fakeStore.copy(entries = emptyList())
        fakeStoresProvider.nextRefreshResult.add(listOf(storeWithNoEntries))
        plugin.onConnect(backgroundScope, pluginConnection)
        pluginConnection.sentData.skipItems(1) // Skip the initially sent data from onConnect.

        pluginConnection.isDesktopPluginActive.value = true
        runCurrent()
        fakeStoresProvider.updates.emit(
            KeyValueEntryUpdate(
                storeName = fakeStore.name,
                operation =
                    EntryAddedOrUpdated(
                        key = "unknown-boolean-key",
                        value = BooleanValue(true),
                    ),
            ),
        )

        pluginConnection.expectNoSentData()
        advanceTimeBy(501.milliseconds)
        assertThat(plugin.stores.get()[fakeStoresProvider]!!.single())
            .isEqualTo(
                storeWithNoEntries.copy(
                    entries =
                        listOf(
                            KeyValueEntry(
                                key = "unknown-boolean-key",
                                value = BooleanValue(true),
                                isEditable = true,
                                lastModifiedMillis = fakeCurrentTimestamp,
                            ),
                        ),
                ),
            )
        assertThat(pluginConnection.awaitSentData())
            .isEqualTo(
                "{\"updateSnapshot\":{\"_0\":{\"stores\":[{\"id\":\"store-id\",\"name\":" +
                    "\"fake-store\",\"entries\":[{\"key\":\"unknown-boolean-key\",\"value\":{\"boolean\":" +
                    "{\"_0\":true}},\"isEditable\":true,\"lastModified\":1000000000," +
                    "\"modificationHistory\":[],\"type\":\"boolean\"}],\"lastUpdated\":1000000000," +
                    "\"sfSymbol\":\"gearshape.fill\",\"isReadOnly\":false,\"supportedTypes\":[" +
                    "\"array\",\"data\",\"boolean\",\"date\",\"float\",\"double\",\"integer16\",\"integer\"," +
                    "\"integer64\",\"dictionary\",\"string\",\"url\",\"unknown\"]" +
                    "}],\"timestamp\":1000000000}}}",
            )
      }
}
