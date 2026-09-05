package xyz.block.echoapp.plugin.accessibility.capture

import android.graphics.Bitmap
import android.view.PixelCopy.SUCCESS
import android.view.PixelCopy.request as requestPixelCopy
import android.view.View
import android.view.Window
import androidx.core.graphics.createBitmap
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult.ViewSnapshotError
import xyz.block.echoapp.plugin.accessibility.capture.ViewCamera.ViewSnapshotResult.ViewSnapshotSuccess
import curtains.Curtains
import curtains.phoneWindow
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/** Responsible for capturing the visual state of the app as a [Bitmap]. */
fun interface ViewCamera {
  sealed interface ViewSnapshotResult {
    data class ViewSnapshotSuccess(
        val bitmap: Bitmap,
        val view: View,
    ) : ViewSnapshotResult

    data class ViewSnapshotError(val message: String) : ViewSnapshotResult
  }

  suspend fun capture(): ViewSnapshotResult
}

/**
 * The default implementation of [ViewCamera].
 *
 * Uses [Curtains](https://github.com/square/curtains) to capture the structure of the UI, then
 * [android.view.PixelCopy] to "screenshot" it to a [Bitmap].
 */
object CurtainsViewCamera : ViewCamera {
  override suspend fun capture(): ViewSnapshotResult {
    val rootView = getRootView() ?: return ViewSnapshotError("No root view found.")
    val bitmap = createBitmap(rootView.width, rootView.height)
    val (left, top) = rootView.getLocationInWindow()
    val destination =
        android.graphics.Rect(
            left,
            top,
            left + rootView.width,
            top + rootView.height,
        )
    val window = rootView.phoneWindow as Window

    return suspendCoroutine { continuation ->
      try {
        requestPixelCopy(
            window,
            destination,
            bitmap,
            { copyResult ->
              continuation.resume(
                  if (copyResult == SUCCESS) {
                    ViewSnapshotSuccess(
                        bitmap = bitmap,
                        view = rootView,
                    )
                  } else {
                    ViewSnapshotError("Could not create a screenshot $copyResult")
                  },
              )
            },
            rootView.handler,
        )
      } catch (e: IllegalArgumentException) {
        e.printStackTrace()
        continuation.resume(
            ViewSnapshotError(
                e.message ?: "Unknown error when capturing View, see logged stack trace."),
        )
      }
    }
  }

  private fun getRootView(): View? {
    return Curtains.rootViews.firstOrNull()?.takeIf { it.phoneWindow is Window }
  }

  private fun View.getLocationInWindow(): Pair<Int, Int> {
    return IntArray(2).also(rootView::getLocationInWindow).let { it[0] to it[1] }
  }
}
