package xyz.block.echoapp.plugin.accessibility

import android.graphics.Bitmap
import android.graphics.Bitmap.CompressFormat.JPEG
import android.view.View
import androidx.annotation.VisibleForTesting
import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.accessibility.capture.AccessibilityElementScanner
import xyz.block.echoapp.plugin.accessibility.capture.CurtainsViewCamera
import xyz.block.echoapp.plugin.accessibility.capture.RadiographyAccessibilityElementScanner
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult.ViewSnapshotError
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult.ViewSnapshotSuccess
import xyz.block.echoapp.plugin.accessibility.internal.AccessibilityCommand
import xyz.block.echoapp.plugin.accessibility.internal.AccessibilityCommand.RequestLiveUpdates
import xyz.block.echoapp.plugin.accessibility.internal.AccessibilityCommand.RequestSnapshot
import xyz.block.echoapp.plugin.accessibility.internal.AccessibilityEvent
import xyz.block.echoapp.plugin.accessibility.internal.AccessibilityEvent.SnapshotEvent
import xyz.block.echoapp.plugin.accessibility.internal.Snapshot
import xyz.block.echoapp.plugin.collectIn
import xyz.block.echoapp.plugin.collectLatestIn
import xyz.block.echoapp.plugin.onEventReceived
import xyz.block.echoapp.plugin.send
import xyz.block.echoapp.plugin.utils.logDebug
import java.io.ByteArrayOutputStream
import kotlin.coroutines.CoroutineContext
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.toByteString
import radiography.Radiography

private const val IMAGE_QUALITY = 100

/**
 * A [ClientPlugin] for showing logged analytics in Echo. This plugin can be instantiated…
 *
 * AccessibilityPlugin(sendLiveUpdatesScope = …)
 *
 * …or it can be overridden with a subclass:
 *
 * @SingleIn(AppScope::class) class MyAccessibilityPlugin @Inject constructor(
 *     @Computation sendLiveUpdatesScope: CoroutineScope, ) : AccessibilityPlugin(
 *       sendLiveUpdatesScope = sendLiveUpdatesScope, ) { override fun logMessage(message: String) {
 *       CustomLogger.log(message) } }
 *
 * Live updates send snapshots on an interval, which defaults to every half second (specified by
 * [sendLiveUpdatesFrequency]). The [sendLiveUpdatesContext] is used to run job for these updates;
 * this should generally be the main thread since UI capture must happen on the main thread. Note
 * that the job only runs when the desktop app requests it, and live updates are only active when
 * the plugin is in view on the desktop app.
 *
 * The [elementScanner] is used to customize how the UI structure (in a11y elements) is retrieved.
 * [Radiography](https://github.com/block/radiography) is used by default.
 *
 * The [viewCamera] is used to customize how the visual state of the app is retrieved. It uses
 * [Curtains](https://github.com/square/curtains) plus [android.view.PixelCopy] by default.
 */
@OptIn(ExperimentalStdlibApi::class)
open class AccessibilityPlugin(
    private val sendLiveUpdatesContext: CoroutineContext = Dispatchers.Main,
    private val sendLiveUpdatesFrequency: Duration = 500.milliseconds,
    private val logHierarchyOnSnapshotRequested: Boolean = true,
    private val elementScanner: AccessibilityElementScanner =
        RadiographyAccessibilityElementScanner,
    private val viewCamera: ViewCamera = CurtainsViewCamera,
) : ClientPlugin {
  private val isLiveUpdatesEnabled = MutableStateFlow(false)

  @VisibleForTesting internal val isLiveUpdatesActive = MutableStateFlow(false)

  override val pluginIdentifier: String = "com.echo.plugin.accessibility"

  @OptIn(ExperimentalCoroutinesApi::class)
  override fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  ) {
    combine(
            isLiveUpdatesEnabled,
            connection.isDesktopPluginActive,
        ) { shouldSendLiveUpdates, isPluginActive ->
          shouldSendLiveUpdates && isPluginActive
        }
        .collectLatestIn(scope) { isLiveUpdatesActive.value = it }

    isLiveUpdatesActive
        .flatMapLatest { liveUpdatesEnabled ->
          if (liveUpdatesEnabled) {
            liveUpdatesIntervalFlow()
          } else {
            // This will result in the job for this flow being stopped, which is why there's a
            // separate
            // isLiveUpdatesActive state flow.
            emptyFlow()
          }
        }
        .collectLatestIn(scope) { connection.trySendA11ySnapshot() }

    connection.onEventReceived<AccessibilityCommand>().collectIn(scope) { command ->
      when (command) {
        RequestSnapshot -> {
          logDebug("Individual snapshot requested.")
          if (logHierarchyOnSnapshotRequested) logDebug(Radiography.scan())
          connection.trySendA11ySnapshot()
        }

        is RequestLiveUpdates -> {
          isLiveUpdatesEnabled.value = command.enabled
        }
      }
    }
  }

  private suspend fun PluginConnection.trySendA11ySnapshot() =
      withContext(sendLiveUpdatesContext) {
        when (val snapshotResult = viewCamera.capture()) {
          is ViewSnapshotSuccess -> {
            sendA11ySnapshot(snapshotResult.view, snapshotResult.bitmap)
          }

          is ViewSnapshotError -> logDebug(snapshotResult.message)
        }
      }

  private fun PluginConnection.sendA11ySnapshot(
      rootView: View,
      viewBitmap: Bitmap,
  ) {
    val base64ImageData =
        ByteArrayOutputStream().use {
          viewBitmap.compress(JPEG, IMAGE_QUALITY, it)
          it.toByteArray().toByteString().base64()
        }
    val event =
        SnapshotEvent(
            snapshot =
                Snapshot(
                    imageData = base64ImageData,
                    elements = elementScanner.scan(rootView),
                ),
        )
    send<AccessibilityEvent>(event)
  }

  private fun liveUpdatesIntervalFlow(): Flow<Unit> = flow {
    logDebug("Starting live updates…")
    while (currentCoroutineContext().isActive) {
      emit(Unit)
      delay(sendLiveUpdatesFrequency)
    }
    logDebug("Live updates stopped.")
  }
}
