package xyz.block.echoapp.plugin.synchub

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.utils.EchoDebugLoggerRule
import xyz.block.echoapp.plugin.utils.FakePluginConnectionRule
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

class SyncHubPluginTest {
  private val fakeTimestamp = "2024-01-15T10:30:00.000Z"
  private var uuidCounter = 0

  @get:Rule val pluginConnectionRule = FakePluginConnectionRule()
  private val pluginConnection = pluginConnectionRule.connection

  @get:Rule val echoDebugLoggerRule = EchoDebugLoggerRule()

  private val plugin =
      SyncHubPlugin(
          currentTimestampProvider = { fakeTimestamp },
          uuidProvider = { "test-uuid-${++uuidCounter}" },
      )

  @Test
  fun `synchub plugin has expected ID`() {
    assertThat(plugin.pluginIdentifier).isEqualTo("com.echo.plugin.synchub")
  }

  @Test
  fun `reportSyncRequest sends request with raw JSON`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    val requestJson = """{"domain_sync_data":{"from_domain_version":"01HQABC"}}"""
    val requestId =
        plugin.reportSyncRequest(
            domain = "kds",
            operationType = SyncOperationType.SYNC_DOMAIN,
            requestJson = requestJson,
        )

    assertThat(requestId).isEqualTo("test-uuid-1")

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"sync_request\":{\"id\":\"test-uuid-1\"," +
                "\"domain\":\"kds\"," +
                "\"timestamp\":\"$fakeTimestamp\"," +
                "\"operationType\":\"sync_domain\"," +
                "\"requestJson\":" +
                "\"{\\\"domain_sync_data\\\":{\\\"from_domain_version\\\":\\\"01HQABC\\\"}}\"" +
                "}}",
        )
  }

  @Test
  fun `reportSyncResponse sends response with raw JSON`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    val responseJson = """{"read_result":{"domain_version":"01HQXYZ"}}"""
    plugin.reportSyncResponse(
        requestId = "req-123",
        domain = "kds",
        operationType = SyncOperationType.SYNC_DOMAIN,
        durationMs = 250,
        responseJson = responseJson,
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"sync_response\":{\"requestId\":\"req-123\"," +
                "\"domain\":\"kds\"," +
                "\"timestamp\":\"$fakeTimestamp\"," +
                "\"operationType\":\"sync_domain\"," +
                "\"durationMs\":250," +
                "\"status\":\"success\"," +
                "\"errorMessage\":\"\"," +
                "\"responseJson\":\"{\\\"read_result\\\":{\\\"domain_version\\\":\\\"01HQXYZ\\\"}}\"" +
                "}}",
        )
  }

  @Test
  fun `reportSyncError sends error response`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    plugin.reportSyncError(
        requestId = "req-456",
        domain = "orders",
        operationType = SyncOperationType.INITIALIZE_DOMAIN,
        durationMs = 5000,
        errorMessage = "Connection timeout",
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"sync_response\":{\"requestId\":\"req-456\"," +
                "\"domain\":\"orders\"," +
                "\"timestamp\":\"$fakeTimestamp\"," +
                "\"operationType\":\"initialize_domain\"," +
                "\"durationMs\":5000," +
                "\"status\":\"error\"," +
                "\"errorMessage\":\"Connection timeout\"," +
                "\"responseJson\":\"\"" +
                "}}",
        )
  }

  @Test
  fun `reportConnectionStatus sends connection status event`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    plugin.reportConnectionStatus(
        domain = "kds",
        isConnectedToLocalHub = true,
        isConnectedToCloudHub = false,
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"connection_status\":{\"domain\":\"kds\"," +
                "\"timestamp\":\"$fakeTimestamp\"," +
                "\"isConnectedToLocalHub\":true," +
                "\"isConnectedToCloudHub\":false" +
                "}}",
        )
  }

  @Test
  fun `reportOutboxStatus sends outbox status event`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    plugin.reportOutboxStatus(
        domain = "orders",
        pendingCommitCount = 7,
    )

    assertThat(pluginConnection.awaitSentData())
        .isEqualTo(
            "{\"outbox_status\":{\"domain\":\"orders\"," +
                "\"timestamp\":\"$fakeTimestamp\"," +
                "\"pendingCommitCount\":7" +
                "}}",
        )
  }

  @Test
  fun `setOnTriggerSync registers callback that is invoked on desktop event`() = runTest {
    var triggeredDomain: String? = null
    plugin.setOnTriggerSync { domain -> triggeredDomain = domain }

    plugin.onConnect(backgroundScope, pluginConnection)

    pluginConnection.receivedData.add("""{"trigger_sync":{"domain":"kds"}}""")

    // Allow coroutine to process
    kotlinx.coroutines.delay(50)

    assertThat(triggeredDomain).isEqualTo("kds")
  }

  @Test
  fun `clearData desktop event is handled without error`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)

    pluginConnection.receivedData.add("""{"clear_data":{}}""")

    // Allow coroutine to process without throwing
    kotlinx.coroutines.delay(50)
  }

  @Test
  fun `full request-response flow`() = runTest {
    plugin.onConnect(backgroundScope, pluginConnection)
    pluginConnection.expectNoSentData()

    val requestJson = """{"domain_sync_data":{"from_domain_version":"v1","commits":[]}}"""
    val requestId =
        plugin.reportSyncRequest(
            domain = "kds",
            operationType = SyncOperationType.SYNC_DOMAIN,
            requestJson = requestJson,
        )

    val requestData = pluginConnection.awaitSentData()
    assertThat(requestData).contains("\"id\":\"$requestId\"")

    val responseJson = """{"read_result":{"domain_version":"v3"}}"""
    plugin.reportSyncResponse(
        requestId = requestId,
        domain = "kds",
        operationType = SyncOperationType.SYNC_DOMAIN,
        durationMs = 150,
        responseJson = responseJson,
    )

    val responseData = pluginConnection.awaitSentData()
    assertThat(responseData).contains("\"requestId\":\"$requestId\"")
    assertThat(responseData).contains("\"durationMs\":150")
    assertThat(responseData).contains("\"status\":\"success\"")
  }
}
