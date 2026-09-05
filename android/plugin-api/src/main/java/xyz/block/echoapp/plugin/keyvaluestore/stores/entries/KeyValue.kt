package xyz.block.echoapp.plugin.keyvaluestore.stores.entries

import android.net.Uri
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
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.ARRAY
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.BLOB
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.BOOLEAN
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.DATE
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.DOUBLE
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.FLOAT
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.INTEGER_16
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.INTEGER_32
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.INTEGER_64
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.MAP
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.STRING
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.UNKNOWN
import xyz.block.echoapp.plugin.keyvaluestore.stores.entries.KeyValueType.URI
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import okio.ByteString

/** A type-safe wrapper for values stored in a [KeyValueEntry]. */
@Suppress("unused")
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
sealed class KeyValue(val type: KeyValueType) {
  @Json(name = TYPE_BLOB)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class BlobValue(val data: ByteString) : KeyValue(BLOB)

  @Json(name = TYPE_BOOLEAN)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class BooleanValue(val bool: Boolean) : KeyValue(BOOLEAN)

  @Json(name = TYPE_DATE)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class DateValue(val milliseconds: Long) : KeyValue(DATE)

  @Json(name = TYPE_FLOAT)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class FloatValue(val number: Float) : KeyValue(FLOAT)

  @Json(name = TYPE_DOUBLE)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class DoubleValue(val number: Double) : KeyValue(DOUBLE)

  @Json(name = TYPE_INTEGER_16)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class Int16Value(val number: Short) : KeyValue(INTEGER_16)

  @Json(name = TYPE_INTEGER_32)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class Int32Value(val number: Int) : KeyValue(INTEGER_32)

  @Json(name = TYPE_INTEGER_64)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class Int64Value(val number: Long) : KeyValue(INTEGER_64)

  @Json(name = TYPE_ARRAY)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class ListValue(val list: List<KeyValue>) : KeyValue(ARRAY) {
    constructor(vararg values: KeyValue) : this(values.toList())
  }

  @Json(name = TYPE_MAP)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class MapValue(val map: Map<String, KeyValue>) : KeyValue(MAP) {
    constructor(vararg entries: Pair<String, KeyValue>) : this(entries.toMap())
  }

  @Json(name = TYPE_URL)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class UriValue(val uri: Uri) : KeyValue(URI)

  @Json(name = TYPE_STRING)
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class StringValue(val string: String) : KeyValue(STRING)

  @Json(name = TYPE_UNKNOWN) data object NullValue : KeyValue(UNKNOWN)
}

fun KeyValue.coerceToString(): String? {
  return when (this) {
    is BlobValue -> data.base64()
    is BooleanValue -> bool.toString()
    is DateValue -> milliseconds.toString()
    is Int16Value -> number.toString()
    is Int32Value -> number.toString()
    is Int64Value -> number.toString()
    is FloatValue -> number.toString()
    is DoubleValue -> number.toString()
    is StringValue -> string
    is UriValue -> uri.toString()
    is ListValue -> list.mapNotNull { it.coerceToString() }.joinToString()
    is MapValue -> map.entries.joinToString { (key, value) -> "$key: ${value.coerceToString()}" }
    NullValue -> null
  }
}

/** Represents the type of a [KeyValue]. */
enum class KeyValueType {
  @Json(name = TYPE_ARRAY) ARRAY,
  @Json(name = TYPE_BLOB) BLOB,
  @Json(name = TYPE_BOOLEAN) BOOLEAN,
  @Json(name = TYPE_DATE) DATE,
  @Json(name = TYPE_FLOAT) FLOAT,
  @Json(name = TYPE_DOUBLE) DOUBLE,
  @Json(name = TYPE_INTEGER_16) INTEGER_16,
  @Json(name = TYPE_INTEGER_32) INTEGER_32,
  @Json(name = TYPE_INTEGER_64) INTEGER_64,
  @Json(name = TYPE_MAP) MAP,
  @Json(name = TYPE_STRING) STRING,
  @Json(name = TYPE_URL) URI,
  @Json(name = TYPE_UNKNOWN) UNKNOWN,
}

private const val TYPE_ARRAY = "array"
private const val TYPE_BLOB = "data"
private const val TYPE_BOOLEAN = "boolean"
private const val TYPE_DATE = "date"
private const val TYPE_FLOAT = "float"
private const val TYPE_DOUBLE = "double"
private const val TYPE_INTEGER_32 = "integer"
private const val TYPE_INTEGER_16 = "integer16"
private const val TYPE_INTEGER_64 = "integer64"
private const val TYPE_MAP = "dictionary"
private const val TYPE_STRING = "string"
private const val TYPE_URL = "url"
private const val TYPE_UNKNOWN = "unknown"
