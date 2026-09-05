package xyz.block.echoapp.plugin.internal

import com.squareup.moshi.FromJson
import com.squareup.moshi.ToJson
import okio.ByteString
import okio.ByteString.Companion.decodeBase64

/** Moshi adapter for ByteString <-> base64 string. */
@Suppress("unused")
internal class ByteStringAdapter {
  @FromJson fun fromJson(string: String?): ByteString? = string?.decodeBase64()

  @ToJson fun toJson(byteString: ByteString?): String? = byteString?.base64()
}
