@file:Suppress("unused")

package xyz.block.echoapp.plugin.utils

import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.utils.loggers.AndroidEchoDebugLoggerImpl

fun ClientPlugin.logVerbose(message: String) {
  EchoDebugLogger.verbose(javaClass.simpleName, message)
}

fun ClientPlugin.logInfo(message: String) {
  EchoDebugLogger.info(javaClass.simpleName, message)
}

fun ClientPlugin.logDebug(message: String) {
  EchoDebugLogger.debug(javaClass.simpleName, message)
}

fun ClientPlugin.logWarn(
    message: String,
    exception: Exception? = null,
) {
  EchoDebugLogger.warn(javaClass.simpleName, message, exception)
}

fun ClientPlugin.logError(
    message: String,
    exception: Exception? = null,
) {
  EchoDebugLogger.error(javaClass.simpleName, message, exception)
}

fun ClientPlugin.logWtf(
    message: String,
    exception: Exception? = null,
) {
  EchoDebugLogger.wtf(javaClass.simpleName, message, exception)
}

/**
 * Enables `EchoClient` and [xyz.block.echoapp.plugin.ClientPlugin]s to log. Client plugins
 * should prefer using the extension functions above instead of calling this singleton directly.
 *
 * Not to be confused with [xyz.block.echoapp.plugin.logging.LoggingPlugin], which interfaces
 * with the Echo desktop app.
 */
object EchoDebugLogger {
  private var installedLogger: LoggerImpl = AndroidEchoDebugLoggerImpl

  fun install(logger: LoggerImpl) {
    installedLogger = logger
  }

  fun verbose(
      tag: String,
      message: String,
  ) = installedLogger.verbose(tag, message)

  fun info(
      tag: String,
      message: String,
  ) = installedLogger.info(tag, message)

  fun debug(
      tag: String,
      message: String,
  ) = installedLogger.debug(tag, message)

  fun warn(
      tag: String,
      message: String,
      exception: Exception? = null,
  ) = installedLogger.warn(tag, message, exception)

  fun error(
      tag: String,
      message: String,
      exception: Exception? = null,
  ) = installedLogger.error(tag, message, exception)

  fun wtf(
      tag: String,
      message: String,
      exception: Exception? = null,
  ) = installedLogger.wtf(tag, message, exception)

  interface LoggerImpl {
    fun verbose(
        tag: String,
        message: String,
    )

    fun info(
        tag: String,
        message: String,
    )

    fun debug(
        tag: String,
        message: String,
    )

    fun warn(
        tag: String,
        message: String,
        exception: Exception? = null,
    )

    fun error(
        tag: String,
        message: String,
        exception: Exception? = null,
    )

    fun wtf(
        tag: String,
        message: String,
        exception: Exception? = null,
    )
  }
}
