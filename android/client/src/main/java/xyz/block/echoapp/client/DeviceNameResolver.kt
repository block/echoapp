@file:Suppress("unused")

package xyz.block.echoapp.client

import android.os.Build

fun interface DeviceNameResolver {
  fun resolve(): String

  /**
   * Derives the device name from [android.os.Build]. Comes out to something like "Google Pixel 6a".
   */
  object DefaultFromBuild : DeviceNameResolver {
    override fun resolve(): String {
      val manufacturer = Build.MODEL
      val model = Build.MODEL
      return buildString {
        if (!model.startsWith(manufacturer, ignoreCase = true)) {
          append(manufacturer.replace('_', ' '))
          append(" ")
        }
        append(model.replace('_', ' '))
      }
    }
  }
}
