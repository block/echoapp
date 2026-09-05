package xyz.block.echoapp.plugin.accessibility

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AccessibilityElement(
    val description: String,
    val identifier: String? = null,
    val hint: String? = null,
    val userInputLabels: List<String>? = null,
    val customActions: List<String>,
    val frame: Rect,
)

@JsonClass(generateAdapter = true)
data class Rect(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
)
