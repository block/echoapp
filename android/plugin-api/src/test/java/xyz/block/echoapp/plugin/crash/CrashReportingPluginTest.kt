package xyz.block.echoapp.plugin.crash

import android.content.Context
import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class CrashReportingPluginTest {
  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val context: Context = RuntimeEnvironment.getApplication()
  private val crashDir = File(context.filesDir, "echo-crashes")
  private val adapter = echoMoshi.adapter(CrashReport::class.java)

  private var originalUncaughtExceptionHandler: Thread.UncaughtExceptionHandler? = null

  @Before
  fun setUp() {
    // Capture whatever handler the test harness installed so tearDown can restore it, rather than
    // leaving a null handler for subsequent tests to inherit.
    originalUncaughtExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
  }

  @After
  fun tearDown() {
    crashDir.deleteRecursively()
    Thread.setDefaultUncaughtExceptionHandler(originalUncaughtExceptionHandler)
  }

  @Test
  fun `plugin has expected ID`() {
    val plugin = CrashReportingPlugin(context)
    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.crash-reporting")
  }

  @Test
  fun `install chains to previous uncaught exception handler`() {
    var previousHandlerCalled = false
    val previousHandler =
        Thread.UncaughtExceptionHandler { _, _ -> previousHandlerCalled = true }
    Thread.setDefaultUncaughtExceptionHandler(previousHandler)

    val plugin = CrashReportingPlugin(context)
    plugin.install()

    val handler = Thread.getDefaultUncaughtExceptionHandler()!!
    handler.uncaughtException(Thread.currentThread(), RuntimeException("test"))

    assertThat(previousHandlerCalled).isTrue()
  }

  @Test
  fun `install persists crash report to disk`() {
    val plugin = CrashReportingPlugin(context)
    plugin.install()

    val handler = Thread.getDefaultUncaughtExceptionHandler()!!
    handler.uncaughtException(
        Thread.currentThread(),
        RuntimeException("test crash"),
    )

    val reports = plugin.storage.readAll()
    assertThat(reports).hasSize(1)
    assertThat(reports[0].exceptionClass).isEqualTo("java.lang.RuntimeException")
    assertThat(reports[0].message).isEqualTo("test crash")
    assertThat(reports[0].threadName).isEqualTo(Thread.currentThread().name)
  }

  @Test
  fun `install persists crash with cause chain`() {
    val plugin = CrashReportingPlugin(context)
    plugin.install()

    val rootCause = IllegalStateException("root cause")
    val exception = RuntimeException("wrapper", rootCause)

    val handler = Thread.getDefaultUncaughtExceptionHandler()!!
    handler.uncaughtException(Thread.currentThread(), exception)

    val reports = plugin.storage.readAll()
    assertThat(reports).hasSize(1)
    assertThat(reports[0].causeChain).hasSize(1)
    assertThat(reports[0].causeChain!![0].exceptionClass)
        .isEqualTo("java.lang.IllegalStateException")
    assertThat(reports[0].causeChain!![0].message).isEqualTo("root cause")
  }

  @Test
  fun `onConnect sends persisted crash reports and deletes files`() = runTest {
    val plugin = CrashReportingPlugin(context)

    val report =
        CrashReport(
            timestamp = 1000L,
            exceptionClass = "java.lang.RuntimeException",
            message = "test crash",
            stackTrace = "fake stack trace",
            threadName = "main",
            threadId = 1L,
            causeChain = null,
        )
    plugin.storage.persist(report)

    plugin.onConnect(backgroundScope, pluginConnection)

    val sentJson = pluginConnection.awaitSentData()
    val sentReport = adapter.fromJson(sentJson)!!
    assertThat(sentReport.exceptionClass).isEqualTo("java.lang.RuntimeException")
    assertThat(sentReport.message).isEqualTo("test crash")

    assertThat(plugin.storage.readAll()).isEmpty()
  }

  @Test
  fun `onConnect sends multiple crash reports`() = runTest {
    val plugin = CrashReportingPlugin(context)

    for (i in 1..3) {
      plugin.storage.persist(
          CrashReport(
              timestamp = i.toLong(),
              exceptionClass = "java.lang.RuntimeException",
              message = "crash $i",
              stackTrace = "stack $i",
              threadName = "main",
              threadId = 1L,
              causeChain = null,
          ),
      )
    }

    plugin.onConnect(backgroundScope, pluginConnection)

    for (i in 1..3) {
      val sentReport = adapter.fromJson(pluginConnection.awaitSentData())!!
      assertThat(sentReport.message).isEqualTo("crash $i")
    }

    assertThat(plugin.storage.readAll()).isEmpty()
  }

  @Test
  fun `onConnect retains persisted reports when send fails`() = runTest {
    pluginConnection.enqueueSendResults(false)
    val plugin = CrashReportingPlugin(context)

    plugin.storage.persist(
        CrashReport(
            timestamp = 1000L,
            exceptionClass = "java.lang.RuntimeException",
            message = "test crash",
            stackTrace = "fake stack trace",
            threadName = "main",
            threadId = 1L,
            causeChain = null,
        ),
    )

    plugin.onConnect(backgroundScope, pluginConnection)

    // Delivery failed, so the report must remain on disk for the next connection attempt.
    assertThat(plugin.storage.readAll()).hasSize(1)
    pluginConnection.expectNoSentData()
  }

  @Test
  fun `onConnect deletes only delivered reports when a later send fails`() = runTest {
    // First frame is accepted, second is refused (closed/full socket).
    pluginConnection.enqueueSendResults(true, false)
    val plugin = CrashReportingPlugin(context)

    for (i in 1..2) {
      plugin.storage.persist(
          CrashReport(
              timestamp = i.toLong(),
              exceptionClass = "java.lang.RuntimeException",
              message = "crash $i",
              stackTrace = "stack $i",
              threadName = "main",
              threadId = 1L,
              causeChain = null,
          ),
      )
    }

    plugin.onConnect(backgroundScope, pluginConnection)

    // Only the delivered report is sent; it is also deleted so it won't be re-sent (duplicated)
    // next time, while the undelivered second report remains for the next connection.
    val sent = adapter.fromJson(pluginConnection.awaitSentData())!!
    assertThat(sent.message).isEqualTo("crash 1")

    val remaining = plugin.storage.readAll()
    assertThat(remaining).hasSize(1)
    assertThat(remaining[0].message).isEqualTo("crash 2")
  }

  @Test
  fun `onConnect does nothing when no persisted reports exist`() = runTest {
    val plugin = CrashReportingPlugin(context)

    plugin.onConnect(backgroundScope, pluginConnection)

    pluginConnection.expectNoSentData()
  }

  @Test
  fun `max crash reports enforced`() {
    val plugin = CrashReportingPlugin(context, maxCrashReports = 3)

    for (i in 1..5) {
      plugin.storage.persist(
          CrashReport(
              timestamp = i.toLong(),
              exceptionClass = "java.lang.RuntimeException",
              message = "crash $i",
              stackTrace = "stack $i",
              threadName = "main",
              threadId = 1L,
              causeChain = null,
          ),
      )
    }

    val reports = plugin.storage.readAll()
    assertThat(reports).hasSize(3)
    assertThat(reports[0].message).isEqualTo("crash 3")
    assertThat(reports[1].message).isEqualTo("crash 4")
    assertThat(reports[2].message).isEqualTo("crash 5")
  }

  @Test
  fun `install is a no-op when called twice`() {
    val plugin = CrashReportingPlugin(context)
    plugin.install()
    val handlerAfterFirstInstall = Thread.getDefaultUncaughtExceptionHandler()

    // A second install must not throw (downgraded from IllegalStateException)...
    plugin.install()

    // ...and must not re-wrap the already-installed handler.
    assertThat(Thread.getDefaultUncaughtExceptionHandler() === handlerAfterFirstInstall).isTrue()
  }

  @Test
  fun `onConnect logs an error when install was never called`() = runTest {
    val recordingLogger = RecordingLogger()
    EchoDebugLogger.install(recordingLogger)

    val plugin = CrashReportingPlugin(context)
    plugin.onConnect(backgroundScope, pluginConnection)

    assertThat(recordingLogger.errors)
        .contains(
            "CrashReportingPlugin was added but install() was never called — " +
                "no crashes will be captured",
        )
  }

  @Test
  fun `onConnect does not warn when install was called`() = runTest {
    val recordingLogger = RecordingLogger()
    EchoDebugLogger.install(recordingLogger)

    val plugin = CrashReportingPlugin(context)
    plugin.install()
    plugin.onConnect(backgroundScope, pluginConnection)

    assertThat(recordingLogger.errors).isEmpty()
  }

  /** Captures error-level logs so tests can assert on the silent-failure warning. */
  private class RecordingLogger : EchoDebugLogger.LoggerImpl {
    val errors = mutableListOf<String>()

    override fun verbose(tag: String, message: String) = Unit

    override fun info(tag: String, message: String) = Unit

    override fun debug(tag: String, message: String) = Unit

    override fun warn(tag: String, message: String, exception: Exception?) = Unit

    override fun error(tag: String, message: String, exception: Exception?) {
      errors += message
    }

    override fun wtf(tag: String, message: String, exception: Exception?) = Unit
  }
}
