package xyz.block.echoapp.plugin.utils.loggers

import android.annotation.SuppressLint
import android.util.Log
import xyz.block.echoapp.plugin.utils.EchoDebugLogger

/** Logs to the Android logcat. */
@SuppressLint("LogNotTimber")
object AndroidEchoDebugLoggerImpl : EchoDebugLogger.LoggerImpl {
  override fun verbose(
      tag: String,
      message: String,
  ) {
    Log.v(tag, message)
  }

  override fun info(
      tag: String,
      message: String,
  ) {
    Log.i(tag, message)
  }

  override fun debug(
      tag: String,
      message: String,
  ) {
    Log.d(tag, message)
  }

  override fun warn(
      tag: String,
      message: String,
      exception: Exception?,
  ) {
    Log.w(tag, message, exception)
  }

  override fun error(
      tag: String,
      message: String,
      exception: Exception?,
  ) {
    Log.e(tag, message, exception)
  }

  override fun wtf(
      tag: String,
      message: String,
      exception: Exception?,
  ) {
    Log.wtf(tag, message, exception)
  }
}
