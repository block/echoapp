package xyz.block.echoapp.plugin.keyvaluestore.providers

import android.content.Context
import android.content.Context.MODE_PRIVATE
import android.content.SharedPreferences
import android.content.SharedPreferences.OnSharedPreferenceChangeListener
import androidx.core.content.edit
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate.Operation.EntriesCleared
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate.Operation.EntryAddedOrUpdated
import xyz.block.echoapp.plugin.keyvaluestore.providers.KeyValueStoresProvider.KeyValueEntryUpdate.Operation.EntryDeleted
import xyz.block.echoapp.plugin.keyvaluestore.stores.KeyValueStore
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.BlobValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.BooleanValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.DateValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.DoubleValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.FloatValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.Int16Value
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.Int32Value
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.Int64Value
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.ListValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.MapValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.NullValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.StringValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValue.UriValue
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueEntry
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.ARRAY
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.BOOLEAN
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.FLOAT
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.INTEGER_32
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.INTEGER_64
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.STRING
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.coerceToString
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.launch

/** A [KeyValueStoresProvider] that reads all shared preferences files for the current app. */
class SharedPrefsKeyValueStoresProvider(
    private val context: Context,
    private val timestampProvider: () -> Long = { System.currentTimeMillis() },
) : KeyValueStoresProvider {
  private var sharedPreferencesMap = mapOf<String, SharedPreferences>()
  private var observationJob: Job? = null

  override val updates = MutableSharedFlow<KeyValueEntryUpdate>(extraBufferCapacity = 1)

  override fun startObservation(coroutineScope: CoroutineScope) {
    observationJob =
        coroutineScope.launch {
          sharedPreferencesMap.values.forEach { prefs ->
            launch { prefs.onKeyValueEntryUpdates().collect { updates.emit(it) } }
          }
        }
  }

  override fun stopObservation() {
    observationJob?.cancel()
    observationJob = null
  }

  override suspend fun refresh(): List<KeyValueStore> {
    sharedPreferencesMap = buildSharedPreferencesFilesMap()
    return sharedPreferencesMap
        .map { (name, sharedPreferences) ->
          KeyValueStore(
              id = name,
              name = name,
              entries = sharedPreferences.all.map { it.toPair().toKeyValueEntry() },
              lastUpdatedMillis = timestampProvider(),
              sfSymbol = getSFSymbol(name),
              supportedTypes = supportedTypes,
          )
        }
        .sortedBy { it.name }
  }

  override suspend fun addOrUpdateValue(
      store: KeyValueStore,
      key: String,
      value: KeyValue,
  ) {
    val sharedPreferences =
        sharedPreferencesMap[store.name]
            ?: error("Shared preferences for store ${store.name} not found.")
    sharedPreferences.edit {
      when (val value = value) {
        is BlobValue -> putString(key, value.data.base64())
        is BooleanValue -> putBoolean(key, value.bool)
        is DateValue -> putLong(key, value.milliseconds)
        is ListValue -> putStringSet(key, value.list.mapNotNull { it.coerceToString() }.toSet())
        is Int16Value -> putInt(key, value.number.toInt())
        is Int32Value -> putInt(key, value.number)
        is Int64Value -> putLong(key, value.number)
        is FloatValue -> putFloat(key, value.number)
        is DoubleValue -> putFloat(key, value.number.toFloat())
        is StringValue -> putString(key, value.string)
        is UriValue -> putString(key, value.uri.toString())
        NullValue -> remove(key)
        is MapValue -> error("Cannot store maps in SharedPreferences.")
      }
    }
  }

  override suspend fun deleteKey(
      store: KeyValueStore,
      key: String,
  ) {
    val sharedPreferences =
        sharedPreferencesMap[store.name]
            ?: error("Shared preferences for store ${store.name} not found.")
    sharedPreferences.edit { remove(key) }
  }

  private fun buildSharedPreferencesFilesMap(): Map<String, SharedPreferences> {
    val prefsFolder = File(context.applicationInfo.dataDir, SHARED_PREFS_DIR)
    val fileNamesList =
        listOf("${getDefaultPrefsName()}$XML_SUFFIX") +
            prefsFolder.list { dir, name -> name.endsWith(XML_SUFFIX) }.orEmpty()

    return buildMap {
      fileNamesList.forEach { fileName ->
        val prefName = fileName.substring(0, fileName.lastIndexOf(XML_SUFFIX))
        put(prefName, context.getSharedPreferences(prefName, MODE_PRIVATE))
      }
    }
  }

  private fun getDefaultPrefsName(): String =
      "${context.packageName}_$DEFAULT_PREFS_FILE_NAME_SUFFIX"

  private fun getSFSymbol(name: String): String =
      when {
        name == getDefaultPrefsName() -> "gearshape.fill"
        name.contains("debug", ignoreCase = true) ||
            name.contains("development", ignoreCase = true) -> "bug.fill"

        name.contains("test", ignoreCase = true) -> "flask.fill"
        name.contains("cache") -> "externaldrive.fill"
        else -> "folder.fill"
      }

  private fun Pair<String, *>.toKeyValueEntry() =
      KeyValueEntry(
          key = first,
          value = second.toKeyValue(),
          isEditable = true,
      )

  private fun Any?.toKeyValue(): KeyValue =
      when (this) {
        null -> NullValue
        is Boolean -> BooleanValue(this)
        is String -> StringValue(this)
        is Short -> Int16Value(this)
        is Int -> Int32Value(this)
        is Long -> Int64Value(this)
        is Float -> FloatValue(this)
        is Double -> DoubleValue(this)
        is Set<*> -> ListValue(map { it.toKeyValue() })
        else -> error("Can't convert value of type ${this::class.java.name} to KeyValue.")
      }

  private fun SharedPreferences.onKeyValueEntryUpdates(): Flow<KeyValueEntryUpdate> = channelFlow {
    val changeListener = OnSharedPreferenceChangeListener { sharedPreferences, key ->
      val storeName =
          sharedPreferencesMap.entries.first { (_, prefs) -> prefs == sharedPreferences }.key
      trySend(
          KeyValueEntryUpdate(
              storeName = storeName,
              operation =
                  when {
                    // If key is null then preferences were cleared; see
                    // `OnSharedPreferenceChangeListener`.
                    key == null -> EntriesCleared
                    !sharedPreferences.contains(key) -> EntryDeleted(key = key)
                    else ->
                        EntryAddedOrUpdated(
                            key = key,
                            value = sharedPreferences.all[key].toKeyValue(),
                        )
                  },
          ),
      )
    }
    registerOnSharedPreferenceChangeListener(changeListener)
    awaitClose { unregisterOnSharedPreferenceChangeListener(changeListener) }
  }

  private companion object {
    const val DEFAULT_PREFS_FILE_NAME_SUFFIX = "preferences"
    const val SHARED_PREFS_DIR = "shared_prefs"
    const val XML_SUFFIX = ".xml"

    val supportedTypes = listOf(STRING, ARRAY, INTEGER_32, INTEGER_64, FLOAT, BOOLEAN)
  }
}
