package xyz.block.echoapp.plugin.analytics

import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.buffered.BufferedClientPlugin
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.adapter
import java.util.UUID
import kotlin.reflect.typeOf

/**
 * A [ClientPlugin] for showing logged analytics in Echo. This plugin can be instantiated…
 *
 * val analyticsPlugin = AnalyticsPlugin( currentTimestampProvider = { dateFormat.format(Date()) },
 * uuidProvider = { UUID.randomUUID().toString() }, ) analyticsPlugin.track( source = event.source,
 * eventName = event.name, properties = event.properties, )
 *
 * …or it can be overridden with a subclass:
 *
 * @SingleIn(AppScope::class) class MyAnalyticsPlugin @Inject constructor( private val
 *   analyticsObserver: AnalyticsObserver, private val currentTime: CurrentTime, private val
 *   dateFormat: DateTimeFormatter, private val unique: Unique, ) : AnalyticsPlugin(
 *   currentTimestampProvider = { dateFormat.format(currentTime.now()) }, uuidProvider =
 *   unique::generate, ) { private var coroutineScope: CoroutineScope? = null
 *
 *   fun start() { coroutineScope?.cancel() coroutineScope = CoroutineScope(Dispatchers.IO).apply {
 *   analyticsObserver.onEvent() .onEach { event -> track( source = event.source, eventName =
 *   event.name, properties = event.properties, ) } .launchIn(this) } }
 *
 *   fun stop() { coroutineScope?.cancel() coroutineScope = null } }
 *
 * Of course, the plugin must be added to an `EchoClient` for it to actually do anything.
 */
@OptIn(ExperimentalStdlibApi::class)
open class AnalyticsPlugin(
    bufferSize: Int = DEFAULT_BUFFER_SIZE,
    private val currentTimestampProvider: () -> String,
    private val uuidProvider: () -> String = { UUID.randomUUID().toString() },
) : BufferedClientPlugin(bufferSize = bufferSize) {
  override val pluginIdentifier: String = "com.echo.plugin.analytics"

  private val propertiesAdapter: JsonAdapter<Map<String, Any?>> =
      echoMoshi.adapter(typeOf<Map<String, Any?>>())

  /**
   * Sends a analytics event to the desktop app. No-ops if there is no active connection.
   *
   * [source]: The source "repository" of the analytics. This can be used to differentiate different
   * analytics systems. [eventName]: The name of the event, like "Click Block Action". [properties]:
   * Additional properties or attributes that go with the event.
   */
  fun track(
      source: String,
      eventName: String,
      properties: Map<String, Any?>,
  ): Boolean {
    return trySendTableRow(
        id = uuidProvider(),
        columnItems =
            mapOf(
                "Time" to currentTimestampProvider(),
                "Source" to source,
                "Event" to eventName,
                "Properties" to propertiesAdapter.toJson(properties),
            ),
    )
  }
}
