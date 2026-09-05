package xyz.block.echoapp.plugin.internal

import com.squareup.moshi.FromJson
import com.squareup.moshi.ToJson

/** Moshi adapter for [Number] <-> JSON long. */
@Suppress("unused")
internal class NumberAdapter {
  @FromJson fun fromJson(long: Long?): Number? = long

  @ToJson fun toJson(number: Number?): Long? = number?.toLong()
}
