package xyz.block.echoapp.sample

import android.app.Application
import xyz.block.echoapp.plugin.crash.CrashReportingPlugin
import timber.log.Timber
import timber.log.Timber.DebugTree

class SampleApplication : Application() {
  /**
   * Installed once here so the uncaught exception handler is registered before any crash can occur,
   * per CrashReportingPlugin's documented usage. The same instance is added to the EchoClient in
   * MainActivity so persisted crash reports are flushed to the desktop app on the next connect.
   */
  lateinit var crashReportingPlugin: CrashReportingPlugin
    private set

  override fun onCreate() {
    super.onCreate()

    if (BuildConfig.DEBUG) {
      Timber.plant(DebugTree())
    }

    crashReportingPlugin = CrashReportingPlugin(this).apply { install() }
  }
}
