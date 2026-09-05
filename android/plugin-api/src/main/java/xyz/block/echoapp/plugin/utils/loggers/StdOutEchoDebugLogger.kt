package xyz.block.echoapp.plugin.utils.loggers

import android.annotation.SuppressLint
import xyz.block.echoapp.plugin.utils.EchoDebugLogger

/** Prints to standard output. */
@SuppressLint("LogNotTimber")
object StdOutEchoDebugLogger : EchoDebugLogger.LoggerImpl {
  override fun verbose(
      tag: String,
      message: String,
  ) {
    println("v/[$tag]: $message")
  }

  override fun info(
      tag: String,
      message: String,
  ) {
    println("i/[$tag]: $message")
  }

  override fun debug(
      tag: String,
      message: String,
  ) {
    println("d/[$tag]: $message")
  }

  override fun warn(
      tag: String,
      message: String,
      exception: Exception?,
  ) {
    println("w/[$tag]: $message")
    exception?.printStackTrace()
  }

  override fun error(
      tag: String,
      message: String,
      exception: Exception?,
  ) {
    println("e/[$tag]: $message")
    exception?.printStackTrace()
  }

  override fun wtf(
      tag: String,
      message: String,
      exception: Exception?,
  ) {
    println("wtf/[$tag]: $message")
    exception?.printStackTrace()
  }
}
