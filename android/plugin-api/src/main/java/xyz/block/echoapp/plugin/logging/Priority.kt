package xyz.block.echoapp.plugin.logging

import android.util.Log

/** A parameter to [LoggingPlugin.log]. */
enum class Priority(val intValue: Int) {
  VERBOSE(Log.VERBOSE),
  DEBUG(Log.DEBUG),
  INFO(Log.INFO),
  WARN(Log.WARN),
  ERROR(Log.ERROR),
  ASSERT(Log.ASSERT),
  ;

  companion object {
    fun fromIntValue(value: Int): Priority {
      return entries.first { it.intValue == value }
    }
  }
}
