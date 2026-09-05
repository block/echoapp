package xyz.block.echoapp.plugin.accessibility.internal

import xyz.block.echoapp.plugin.accessibility.AccessibilityElement
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
internal sealed class AccessibilityEvent {
  @Json(name = "snapshot")
  @JsonClass(generateAdapter = true, generator = "sealed-swift-compat")
  data class SnapshotEvent(
      val snapshot: Snapshot,
  ) : AccessibilityEvent()
}

@JsonClass(generateAdapter = true)
internal data class Snapshot(
    val imageData: String,
    val elements: List<AccessibilityElement>,
)
