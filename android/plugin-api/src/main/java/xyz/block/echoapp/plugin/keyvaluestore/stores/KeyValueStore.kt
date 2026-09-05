package xyz.block.echoapp.plugin.keyvaluestore.stores

import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.NullValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueEntry
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** A collection of key-value entries representing a store, like `SharedPreferences`. */
@JsonClass(generateAdapter = true)
data class KeyValueStore(
    val id: String,
    val name: String,
    val entries: List<KeyValueEntry>,
    @Json(name = "lastUpdated") val lastUpdatedMillis: Long,
    val sfSymbol: String = "gearshape.fill",
    val isReadOnly: Boolean = false,
    val supportedTypes: List<KeyValueType> = KeyValueType.entries,
)

fun KeyValueStore.addOrUpdateEntry(
    key: String,
    update: KeyValueEntry.() -> KeyValueEntry,
): KeyValueStore {
  val entryIndex = entries.indexOfFirst { it.key == key }
  return copy(
      entries =
          entries.asMutableList().apply {
            if (entryIndex > -1) {
              val updatedEntry = entries[entryIndex].update()
              set(entryIndex, updatedEntry)
            } else {
              add(
                  KeyValueEntry(
                          key = key,
                          value = NullValue,
                          isEditable = !isReadOnly,
                      )
                      .update(),
              )
            }
          },
  )
}

fun KeyValueStore.removeEntry(key: String): KeyValueStore {
  return copy(entries = entries.filterNot { it.key == key })
}

fun KeyValueStore.clearEntries(): KeyValueStore = copy(entries = emptyList())

@Throws(IllegalStateException::class)
fun List<KeyValueStore>.withUpdatedStore(
    name: String,
    update: KeyValueStore.() -> KeyValueStore,
): List<KeyValueStore> {
  val storeIndex =
      indexOfFirst { it.name == name }.takeIf { it > -1 }
          ?: error("Store with name $name not found.")
  return asMutableList().apply { set(storeIndex, get(storeIndex).update()) }
}

private inline fun <reified T> List<T>.asMutableList(): MutableList<T> =
    this as? ArrayList<T> ?: toMutableList()
