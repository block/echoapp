package xyz.block.echoapp.plugin.utils

import xyz.block.echoapp.plugin.utils.loggers.StdOutEchoDebugLogger
import org.junit.rules.ExternalResource

class EchoDebugLoggerRule : ExternalResource() {
  override fun before() {
    EchoDebugLogger.install(StdOutEchoDebugLogger)
  }
}
