package xyz.block.echoapp.plugin.crash

import com.squareup.moshi.JsonAdapter
import java.io.File
import java.util.UUID

internal class CrashFileStorage(
    private val crashDir: File,
    private val maxCrashReports: Int,
    private val adapter: JsonAdapter<CrashReport>,
) {
  init {
    // The directory location never changes, so create it once rather than on every persist().
    crashDir.mkdirs()
  }

  fun persist(report: CrashReport) {
    val file = File(crashDir, "crash_${report.timestamp}_${UUID.randomUUID()}.json")
    file.writeText(adapter.toJson(report))
    enforceMaxReports()
  }

  /**
   * Reads all persisted crash reports, oldest first, each paired with its backing file so callers
   * can delete it individually as soon as it has been delivered.
   */
  fun read(): List<PersistedCrashReport> {
    if (!crashDir.exists()) return emptyList()
    return crashDir
        .listFiles { file -> file.extension == "json" }
        .orEmpty()
        .sortedBy { it.name }
        .mapNotNull { file ->
          val report =
              try {
                adapter.fromJson(file.readText())
              } catch (_: Exception) {
                null
              }
          report?.let { PersistedCrashReport(it, file) }
        }
  }

  /** Convenience view of [read] returning just the [CrashReport]s, oldest first. */
  fun readAll(): List<CrashReport> = read().map { it.report }

  private fun enforceMaxReports() {
    val files =
        crashDir
            .listFiles { file -> file.extension == "json" }
            .orEmpty()
            .sortedBy { it.name }
    if (files.size > maxCrashReports) {
      files.take(files.size - maxCrashReports).forEach { it.delete() }
    }
  }
}

/** A persisted [report] paired with its backing [file], so it can be deleted once handled. */
internal class PersistedCrashReport(
    val report: CrashReport,
    private val file: File,
) {
  fun delete() {
    file.delete()
  }
}
