package xyz.block.echoapp.plugin.tables

import xyz.block.echoapp.plugin.PluginConnection
import com.squareup.moshi.JsonClass

/** Represents the row of a table in the Echo desktop UI. See [PluginConnection.sendTableRow]. */
@JsonClass(generateAdapter = true)
data class EchoTableRow(
    val id: String,
    val columnItems: Map<String, String>,
)
