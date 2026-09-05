package xyz.block.echoapp.client.internal

internal enum class ClientPluginLifecycleEvent(private val eventName: String) {
  ACTIVE("onDesktopPluginActive"),
  INACTIVE("onDesktopPluginInactive"),
  ;

  override fun toString(): String {
    return "\"${javaClass.simpleName}.$eventName\""
  }

  companion object {
    fun fromString(name: String) = entries.find { it.toString() == name }
  }
}
