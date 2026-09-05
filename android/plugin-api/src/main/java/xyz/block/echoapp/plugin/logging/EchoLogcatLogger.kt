package xyz.block.echoapp.plugin.logging

import logcat.LogPriority
import logcat.LogPriority.DEBUG
import logcat.LogcatLogger

/**
 * A [Logcat](https://github.com/square/logcat) logger that can be installed to relay logs to Echo.
 *
 * LogcatLogger.install(EchoLogcatLogger(loggingPlugin))
 */
class EchoLogcatLogger(
    minPriority: LogPriority = DEBUG,
    private val loggingPlugin: LoggingPlugin,
) : LogcatLogger {
  private val minPriorityInt: Int = minPriority.priorityInt

  override fun isLoggable(priority: LogPriority): Boolean = priority.priorityInt >= minPriorityInt

  override fun log(
      priority: LogPriority,
      tag: String,
      message: String,
  ) {
    loggingPlugin.log(
        priority = Priority.fromIntValue(priority.priorityInt),
        tag = tag,
        message = message,
    )
  }
}
