@file:Suppress("unused")

package xyz.block.echoapp.client

import android.annotation.SuppressLint
import android.content.Context
import android.provider.Settings.Secure
import android.provider.Settings.Secure.ANDROID_ID

/**
 * Used to provide device IDs to Echo.
 *
 * Device IDs must be unique per device, and stable between app sessions; it should be the same
 * between multiple apps on a given device, and it should not change between app sessions.
 */
fun interface DeviceIdentifierResolver {
  fun resolve(): String

  /**
   * Derives the device ID from
   * [https://developer.android.com/reference/android/provider/Settings.Secure.html#ANDROID_ID].
   */
  @SuppressLint("HardwareIds")
  class DefaultFromAndroidId(val context: Context) : DeviceIdentifierResolver {
    override fun resolve(): String = Secure.getString(context.contentResolver, ANDROID_ID)
  }
}
