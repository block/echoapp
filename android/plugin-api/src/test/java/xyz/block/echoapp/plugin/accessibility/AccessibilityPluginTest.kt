package xyz.block.echoapp.plugin.accessibility

import android.graphics.Bitmap
import android.graphics.Bitmap.Config.ARGB_8888
import android.view.ViewStub
import androidx.test.core.app.ApplicationProvider.getApplicationContext
import app.cash.turbine.plusAssign
import app.cash.turbine.test
import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult.ViewSnapshotError
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult.ViewSnapshotSuccess
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnection
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlin.coroutines.CoroutineContext
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class) // For Bitmaps
class AccessibilityPluginTest {
  private val fakeAccessibilityElements =
      listOf(
          AccessibilityElement(
              description = "A fake a11y element",
              identifier = "fake-a11y-element-1",
              hint = "Hello, world!",
              userInputLabels = listOf("a label"),
              customActions = listOf("an action"),
              frame = Rect(0f, 0f, 50f, 50f),
          ),
      )
  private var nextViewSnapshotResult: ViewSnapshotResult =
      ViewSnapshotError("Default result is an error")

  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  @Test
  fun `accessibility plugin has expected ID`() {
    val plugin = createPlugin()

    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.accessibility")
  }

  @Test
  fun `when onDataReceived gets requestSnapshot command, then a snapshot is serialized and sent`() =
      runTest {
        val plugin = createPlugin()

        plugin.onConnect(backgroundScope, pluginConnection)
        pluginConnection.expectNoSentData()

        setNextViewSnapshotResultSuccess()
        pluginConnection.receivedData += "{\"requestSnapshot\":{}}"

        pluginConnection.assertSnapshotSentAndReset()
      }

  @Test
  fun `when isDesktopPluginActive state changes, then live updates start or stop`() = runTest {
    val plugin = createPlugin()

    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    plugin.assertLiveUpdatesStopped()
    pluginConnection.receivedData += "{\"sendLiveUpdates\":{\"_0\":true}}"
    pluginConnection.isDesktopPluginActive.value = true
    plugin.assertLiveUpdatesStarted()

    pluginConnection.isDesktopPluginActive.value = false
    plugin.assertLiveUpdatesStopped()
  }

  @Test
  fun `when onDataReceived gets sendLiveUpdates command, then live updates start or stop`() =
      runTest {
        val plugin = createPlugin()

        plugin.onConnect(backgroundScope, pluginConnection)
        pluginConnection.isDesktopPluginActive.value = true
        pluginConnection.expectNoSentData()
        plugin.assertLiveUpdatesStopped()

        pluginConnection.receivedData += "{\"sendLiveUpdates\":{\"_0\":true}}"
        plugin.assertLiveUpdatesStarted()

        pluginConnection.receivedData += "{\"sendLiveUpdates\":{\"_0\":false}}"
        plugin.assertLiveUpdatesStopped()
      }

  @Test
  fun `when live updates are running, then snapshots are periodically sent in the background`() =
      runTest {
        val plugin = createPlugin(sendLiveUpdatesContext = StandardTestDispatcher(testScheduler))

        plugin.onConnect(backgroundScope, pluginConnection)
        pluginConnection.isDesktopPluginActive.value = true
        pluginConnection.expectNoSentData()

        setNextViewSnapshotResultSuccess()
        pluginConnection.receivedData += "{\"sendLiveUpdates\":{\"_0\":true}}"
        runCurrent()
        plugin.assertLiveUpdatesStarted()

        // Initial immediate snapshot is sent.
        runCurrent()
        pluginConnection.assertSnapshotSentAndReset()
        runCurrent()

        // Follow-up live update.
        advanceTimeBy(250.milliseconds)
        runCurrent()
        pluginConnection.expectNoSentData()
        advanceTimeBy(251.milliseconds)
        runCurrent()
        pluginConnection.assertSnapshotSentAndReset()

        // Follow-up live update.
        advanceTimeBy(250.milliseconds)
        runCurrent()
        pluginConnection.expectNoSentData()
        advanceTimeBy(251.milliseconds)
        runCurrent()
        pluginConnection.assertSnapshotSentAndReset()

        backgroundScope.cancel()
      }

  private fun createPlugin(
      sendLiveUpdatesContext: CoroutineContext = Dispatchers.Default,
  ): AccessibilityPlugin {
    return AccessibilityPlugin(
        sendLiveUpdatesContext = sendLiveUpdatesContext,
        elementScanner = { fakeAccessibilityElements },
        viewCamera = { nextViewSnapshotResult },
    )
  }

  private fun setNextViewSnapshotResultSuccess() {
    val snapshotBitmap = Bitmap.createBitmap(100, 100, ARGB_8888)
    nextViewSnapshotResult =
        ViewSnapshotSuccess(
            bitmap = snapshotBitmap,
            view = ViewStub(getApplicationContext()),
        )
  }

  private suspend fun FakePluginConnection.assertSnapshotSentAndReset() {
    assertThat(awaitSentData())
        .isEqualTo(
            "{\"snapshot\":{\"_0\":{" +
                "\"imageData\":\"$EXPECTED_BITMAP_BASE64_DATA\"," +
                "\"elements\":[{" +
                "\"description\":\"A fake a11y element\"," +
                "\"identifier\":\"fake-a11y-element-1\"," +
                "\"hint\":\"Hello, world!\"," +
                "\"userInputLabels\":[\"a label\"]," +
                "\"customActions\":[\"an action\"]," +
                "\"frame\":{\"x\":0.0,\"y\":0.0,\"width\":50.0,\"height\":50.0}" +
                "}]" +
                "}}}",
        )
    reset()
  }

  private suspend fun AccessibilityPlugin.assertLiveUpdatesStarted() {
    if (isLiveUpdatesActive.value) return
    isLiveUpdatesActive.test(name = "isLiveUpdatesActive") {
      if (awaitItem()) return@test
      assertWithMessage("Expected live updates to be started").that(awaitItem()).isTrue()
    }
  }

  private suspend fun AccessibilityPlugin.assertLiveUpdatesStopped() {
    if (!isLiveUpdatesActive.value) return
    isLiveUpdatesActive.test(name = "isLiveUpdatesActive") {
      if (!awaitItem()) return@test
      assertWithMessage("Expected live updates to be stopped").that(awaitItem()).isFalse()
    }
  }
}

private const val EXPECTED_BITMAP_BASE64_DATA =
    "/9j/4AAQSkZJRgABAgAAAQABAAD/2wBDAAEBAQEBAQEBAQ" +
        "EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQ" +
        "EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCABkAGQDASIAAh" +
        "EBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMU" +
        "EGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaG" +
        "lqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5u" +
        "fo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AA" +
        "ECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVl" +
        "dYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1d" +
        "bX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD/AD/6KKKACiiigAooooAKKKKACiiigAooooAKKKKACi" +
        "iigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKK" +
        "KACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoooo" +
        "AKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP//Z"
