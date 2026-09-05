package xyz.block.echoapp.plugin.logging

import timber.log.Timber

/**
 * A [Timber](https://github.com/JakeWharton/timber) tree that can be planted to relay logs to Echo.
 *
 * Timber.plant(EchoTree(loggingPlugin))
 */
class EchoTree(
    private val plugin: LoggingPlugin,
) : Timber.Tree() {
  override fun log(
      priority: Int,
      tag: String?,
      message: String,
      t: Throwable?,
  ) {
    plugin.log(
        priority = Priority.fromIntValue(priority),
        tag = tag.orEmpty(),
        message = message,
        throwable = t,
    )
  }
}
