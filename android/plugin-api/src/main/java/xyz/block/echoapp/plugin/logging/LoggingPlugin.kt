package xyz.block.echoapp.plugin.logging

import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.buffered.BufferedClientPlugin
import xyz.block.echoapp.plugin.buffered.DEFAULT_BUFFER_SIZE
import java.util.UUID

/**
 * A [ClientPlugin] for showing logs (like logcats) in Echo. This plugin can be instantiated…
 *
 * val loggingPlugin = LoggingPlugin( currentTimestampProvider = { dateFormat.format(Date()) },
 * uuidProvider = { UUID.randomUUID().toString() }, ) loggingPlugin.log( // Or something like
 * Priority.DEBUG priority = Priority.fromIntValue(logEvent.priority), tag = logEvent.tag, message =
 * logEvent.message, logEvent.throwable, )
 *
 * …or it can be overridden with a subclass:
 *
 * @SingleIn(AppScope::class) class MyLoggingPlugin @Inject constructor( private val currentTime:
 *   CurrentTime, private val dateFormat: DateTimeFormatter, private val logObserver: LogObserver,
 *   private val unique: Unique, ) : LoggingPlugin( currentTimestampProvider = {
 *   dateFormat.format(currentTime.now()) }, uuidProvider = unique::generate, ) { private var
 *   coroutineScope: CoroutineScope? = null
 *
 *   fun start() { coroutineScope?.cancel() coroutineScope = CoroutineScope(Dispatchers.IO).apply {
 *   logObserver.onLogEvent() .onEach { logEvent -> log( // Or something like Priority.DEBUG
 *   priority = Priority.fromIntValue(logEvent.priority), tag = logEvent.tag, message =
 *   logEvent.message, throwable = logEvent.throwable, ) } .launchIn(this) } }
 *
 *   fun stop() { coroutineScope?.cancel() coroutineScope = null } }
 *
 * Of course, the plugin must be added to an `EchoClient` for it to actually do anything. See
 * [EchoTree] for Timber, or [EchoLogcatLogger] for square/logcat.
 */
open class LoggingPlugin(
    bufferSize: Int = DEFAULT_BUFFER_SIZE,
    private val currentTimestampProvider: () -> String,
    private val uuidProvider: () -> String = { UUID.randomUUID().toString() },
) : BufferedClientPlugin(bufferSize = bufferSize) {
  override val pluginIdentifier = "com.echo.plugin.logging"

  /**
   * Sends a log event to the desktop app.
   *
   * [priority]: The priority of the event, like [Priority.DEBUG]. See also [Priority.fromIntValue].
   * [tag]: The tag of the event, like the logcat tag. [message]: The message of the log.
   * [throwable]: An optional exception attached to the log, i.e. from `Log.e`.
   */
  fun log(
      priority: Priority,
      tag: String,
      message: String,
      throwable: Throwable? = null,
  ): Boolean {
    return trySendTableRow(
        id = uuidProvider(),
        columnItems =
            mapOf(
                "Time" to currentTimestampProvider(),
                "Priority" to priority.name,
                "Tag" to tag,
                "Message" to message + throwable?.let { " $it" }.orEmpty(),
            ),
    )
  }
}
