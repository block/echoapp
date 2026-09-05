package xyz.block.echoapp.plugin.utils

import app.cash.turbine.Turbine
import xyz.block.echoapp.plugin.PluginConnection
import xyz.block.echoapp.plugin.PluginConnection.Companion.echoMoshi
import xyz.block.echoapp.plugin.tables.EchoTableRow
import com.squareup.moshi.JsonAdapter
import kotlin.reflect.KClass
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.receiveAsFlow
import org.junit.rules.ExternalResource

class FakePluginConnectionRule(
    val connection: FakePluginConnection = FakePluginConnection(),
) : ExternalResource() {
  override fun after() {
    with(connection) {
      runCatching { sentData.ensureAllEventsConsumed() }
          .exceptionOrNull()
          ?.let { throw AssertionError(it) }
      reset()
    }
  }
}

class FakePluginConnection : PluginConnection {
  private val echoTableRowAdapter = echoMoshi.adapter(EchoTableRow::class.java)
  private var sentRows = 0

  val sentData = Turbine<String>(name = "sentData")
  val receivedData = Turbine<String>(name = "eventsReceived")

  override val isDesktopPluginActive = MutableStateFlow(false)

  /**
   * Results returned by successive [send] calls, consumed in order; when empty, [send] succeeds.
   * Lets tests model a socket that accepts some frames and then refuses (returns `false`). A frame
   * that "fails" is not recorded in [sentData], mirroring an undelivered message.
   */
  private val sendResults = ArrayDeque<Boolean>()

  fun enqueueSendResults(vararg results: Boolean) {
    sendResults.addAll(results.toList())
  }

  fun expectNoSentData() {
    sentData.expectNoEvents()
  }

  suspend fun awaitSentData(): String {
    return sentData.awaitItem()
  }

  override fun send(data: String): Boolean {
    val accepted = sendResults.removeFirstOrNull() ?: true
    if (!accepted) return false
    sentData.add(data)
    return true
  }

  override fun send(
      typeForAdapter: KClass<*>,
      model: Any,
  ): Boolean {
    val adapter = echoMoshi.adapter(typeForAdapter.java) as JsonAdapter<Any>
    return send(adapter.toJson(model))
  }

  override fun sendTableRow(
      id: String?,
      columnItems: Map<String, String>,
  ): Boolean {
    return send(
        echoTableRowAdapter.toJson(
            EchoTableRow(
                id = "fake-row-id-${++sentRows}",
                columnItems = columnItems,
            ),
        ),
    )
  }

  override fun <T : Any> onEventReceived(type: KClass<T>): Flow<T> {
    val adapter = echoMoshi.adapter(type.java)
    return receivedData.asChannel().receiveAsFlow().mapNotNull { data -> adapter.fromJson(data) }
  }

  fun reset() {
    sentRows = 0
    sendResults.clear()
  }
}
