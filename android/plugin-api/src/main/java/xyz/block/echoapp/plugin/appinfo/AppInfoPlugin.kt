package xyz.block.echoapp.plugin.appinfo

import xyz.block.echoapp.plugin.ClientPlugin
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.collectLatestIn
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonClass
import com.squareup.moshi.adapter
import kotlin.reflect.typeOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.onStart

/**
 * A convenience to create an instance of [AppInfoPlugin] and with [AppInfoPlugin.buildAppInfo]
 * implemented inline. This can be used if the app info does not change.
 *
 * val plugin = AppInfoPlugin { scope("Tokens") { entry("Merchant", "…") entry("Unit", "…") }
 * scope("Device") { entry("Manufacturer", "…") entry("Model", "…") } }
 */
fun AppInfoPlugin(builder: AppInfoBuilder.() -> Unit): AppInfoPlugin {
  return object : AppInfoPlugin() {
    override fun AppInfoBuilder.buildAppInfo() = builder()
  }
}

/**
 * A [ClientPlugin] for showing info about the connected app in Echo. This plugin can be
 * "instantiated" using the top-level function above…
 *
 * val appInfoPlugin = AppInfoPlugin { scope("Tokens") { entry("Merchant", "…") entry("Unit", "…") }
 * scope("Device") { entry("Manufacturer", "…") entry("Model", "…") } } // Call to re-evaluate the
 * lambda and generate new info. appInfoPlugin.sendLatestAppInfo()
 *
 * …or it can be overridden with a subclass:
 *
 * @SingleIn(AppScope::class) class MyAppInfoProvider @Inject constructor( private val
 *   merchantTokenProvider: MerchantTokenProvider, private val unitTokenProvider: UnitTokenProvider,
 *   private val deviceInfoProvider: DeviceInfoProvider, ) : AppInfoPlugin() { override suspend fun
 *   onDesktopPluginActive() { super.onDesktopPluginActive() // Call to re-evaluate the lambda and
 *   generate new info. sendLatestAppInfo() }
 *
 *   override fun AppInfoBuilder.buildAppInfo() { scope("Tokens") { entry("Merchant",
 *   merchantTokenProvider.get()) entry("Unit", merchantTokenProvider.get()) } scope("Device") {
 *   entry("Manufacturer", deviceInfoProvider.manufacturer) entry("Model", deviceInfoProvider.model)
 *   } } }
 *
 *   Of course, the plugin must be added to an `EchoClient` for it to actually do anything.
 */
@Suppress("unused")
@OptIn(ExperimentalStdlibApi::class)
abstract class AppInfoPlugin : ClientPlugin {
  override val pluginIdentifier: String = "com.echo.plugin.appinfo"

  private val appInfoEntryAdapter: JsonAdapter<List<AppInfoEntry>> =
      echoMoshi.adapter(typeOf<List<AppInfoEntry>>())

  private val sendLatestAppInfoQueue = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

  /**
   * Used to build the sections shown in the desktop plugin.
   *
   * override fun AppInfoBuilder.buildAppInfo() { scope("Tokens") { entry("Merchant", "…")
   * entry("Unit", "…") } scope("Device") { entry("Manufacturer", "…") entry("Model", "…") } }
   */
  abstract fun AppInfoBuilder.buildAppInfo()

  /** Invokes [buildAppInfo] and sends the latest app info to the desktop plugin. */
  fun sendLatestAppInfo() {
    sendLatestAppInfoQueue.tryEmit(Unit)
  }

  override fun onConnect(
      scope: CoroutineScope,
      connection: PluginConnection,
  ) {
    sendLatestAppInfoQueue
        .onStart { emit(Unit) }
        .collectLatestIn(scope) {
          val entries = AppInfoBuilder().apply { buildAppInfo() }.toAppInfoEntries()
          connection.send(appInfoEntryAdapter.toJson(entries))
        }
  }
}

@JsonClass(generateAdapter = true)
internal data class AppInfoEntry(
    val scope: String,
    val key: String,
    val value: String,
)
