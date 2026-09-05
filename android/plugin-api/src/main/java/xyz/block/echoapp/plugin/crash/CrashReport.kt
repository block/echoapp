package xyz.block.echoapp.plugin.crash

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class CrashReport(
    val timestamp: Long,
    val exceptionClass: String,
    val message: String?,
    val stackTrace: String,
    val threadName: String,
    val threadId: Long,
    val causeChain: List<CauseInfo>?,
)

@JsonClass(generateAdapter = true)
data class CauseInfo(
    val exceptionClass: String,
    val message: String?,
)
