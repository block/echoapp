package xyz.block.echoapp.plugin.accessibility.internal

import xyz.block.echoapp.plugin.accessibility.AccessibilityPlugin
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/** Represents commands that are sent to [AccessibilityPlugin] *from* the desktop app. */
@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed interface AccessibilityCommand {
  @Json(name = "requestSnapshot") data object RequestSnapshot : AccessibilityCommand

  @Json(name = "sendLiveUpdates")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class RequestLiveUpdates(
      val enabled: Boolean,
  ) : AccessibilityCommand
}
