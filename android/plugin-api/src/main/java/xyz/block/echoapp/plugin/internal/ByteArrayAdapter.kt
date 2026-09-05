package xyz.block.echoapp.plugin.internal

import com.squareup.moshi.FromJson
import com.squareup.moshi.ToJson
import java.util.Base64

/** Moshi adapter for ByteArray <-> base64 string. */
@Suppress("unused")
internal class ByteArrayAdapter {
  @FromJson
  fun fromJson(string: String?): ByteArray? {
    if (string == null) return null
    return Base64.getDecoder().decode(string)
  }

  @ToJson
  fun toJson(bytes: ByteArray?): String? {
    if (bytes == null) return null
    return Base64.getEncoder().encodeToString(bytes)
  }
}
