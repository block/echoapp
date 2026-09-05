package xyz.block.echoapp.plugin.crash

import android.content.Context
import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.utils.logError
import xyz.block.echoapp.plugin.utils.logInfo
import java.io.File
import java.util.IdentityHashMap
import kotlinx.coroutines.CoroutineScope

/**
 * A [ClientPlugin] that captures uncaught JVM exceptions and sends them to the Echo desktop app on
 * the next connection. Because the WebSocket connection dies with the process during a crash, crash
 * data is persisted to disk and sent when the app reconnects.
 *
 * ```kotlin
 * val crashReportingPlugin = CrashReportingPlugin(context)
 * crashReportingPlugin.install() // Arms the uncaught-exception handler.
 *
 * val client = EchoClient.Builder(context)
 *   .addPlugins(crashReportingPlugin)
 *   .build()
 * ```
 *
 * Call [install] early in your app's lifecycle (e.g. in `Application.onCreate()`) so startup crashes
 * are captured. The handler chains to whichever handler is already installed when [install] runs,
 * delegating to it after persisting — so Echo does not suppress other crash reporters such as
 * Bugsnag or Firebase Crashlytics.
 *
 * Ordering matters for Echo's own capture: a handler that replaces the default *after* [install]
 * runs without delegating to the previous one would stop Echo from seeing crashes. To be safe,
 * install Echo after such reporters initialize so it sits at the top of the handler chain. (Firebase
 * Crashlytics auto-initializes via a `ContentProvider` before `Application.onCreate()`, so calling
 * [install] there already places Echo above Crashlytics.)
 *
 * If [install] is never called the plugin still connects but captures nothing; [onConnect] logs an
 * error in that case to surface the misconfiguration.
 *
 * The [maxCrashReports] constructor parameter (default: 5) controls how many crash reports are
 * retained on disk. Older reports are pruned when the limit is exceeded.
 */
class CrashReportingPlugin(
    context: Context,
    maxCrashReports: Int = 5,
) : ClientPlugin {
  override val pluginIdentifier = "com.echo.plugin.crash-reporting"

  private val adapter = echoMoshi.adapter(CrashReport::class.java)

  internal val storage =
      CrashFileStorage(
          crashDir = File(context.filesDir, "echo-crashes"),
          maxCrashReports = maxCrashReports,
          adapter = adapter,
      )

  private var installed = false

  fun install() {
    if (installed) {
      // A duplicate install is harmless, so no-op rather than throwing and taking down the host app
      // over a wiring mistake in a debugging aid.
      logError("CrashReportingPlugin.install() has already been called; ignoring")
      return
    }
    installed = true
    val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
    Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
      try {
        storage.persist(throwable.toCrashReport(thread))
      } catch (_: Exception) {
        // Best-effort — the process is dying, nothing we can do if this fails.
      }
      previousHandler?.uncaughtException(thread, throwable)
    }
  }

  override fun onConnect(scope: CoroutineScope, connection: PluginConnection) {
    // The framework has no startup hook, so onConnect is the first point we know the plugin is
    // wired in. Surface the silent-failure case where it was added but install() was never called —
    // otherwise nothing captures crashes yet everything looks normal.
    if (!installed) {
      logError("CrashReportingPlugin was added but install() was never called — no crashes will be captured")
    }

    val pendingReports = storage.read()
    if (pendingReports.isEmpty()) return

    logInfo("Sending ${pendingReports.size} persisted crash report(s) to desktop")
    for (persisted in pendingReports) {
      val sent =
          try {
            connection.send(adapter.toJson(persisted.report))
          } catch (e: Exception) {
            logError("Failed to send crash report", e)
            false
          }
      // `send` signals a closed/full socket by returning false rather than throwing. In either
      // failure case, keep the remaining persisted files so the next connection attempt can retry
      // instead of permanently dropping reports that were never delivered.
      if (!sent) return
      // Delete each file as soon as it is delivered so a later failure can't re-send (and
      // duplicate) an already-delivered report on the next connection.
      persisted.delete()
    }
  }
}

internal fun Throwable.toCrashReport(thread: Thread): CrashReport {
  return CrashReport(
      timestamp = System.currentTimeMillis(),
      exceptionClass = this::class.java.name,
      message = message,
      stackTrace = stackTraceToString(),
      threadName = thread.name,
      threadId = thread.id,
      causeChain = buildCauseChain(),
  )
}

private fun Throwable.buildCauseChain(): List<CauseInfo>? {
  val causes = mutableListOf<CauseInfo>()
  val seen = IdentityHashMap<Throwable, Unit>()
  var current = cause
  while (current != null && seen.put(current, Unit) == null) {
    // Only the class and message are stored per cause; the full frames for the entire cause chain
    // already live in CrashReport.stackTrace (Throwable.stackTraceToString() includes "Caused by").
    causes +=
        CauseInfo(
            exceptionClass = current::class.java.name,
            message = current.message,
        )
    current = current.cause
  }
  return causes.ifEmpty { null }
}
