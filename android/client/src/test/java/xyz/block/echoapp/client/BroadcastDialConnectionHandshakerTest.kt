package xyz.block.echoapp.client

import com.google.common.truth.Truth.assertThat
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import xyz.block.echoapp.plugin.utils.loggers.StdOutEchoDebugLogger
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for the dial-decision logic and the request latch of
 * [BroadcastDialConnectionHandshaker]. The [android.content.BroadcastReceiver] registration is thin
 * Android glue; the behavior worth pinning is "which broadcasts produce a dial, to which URL, and
 * when it becomes observable", which [BroadcastDialConnectionHandshaker.connectionRequestFor] and
 * [BroadcastDialConnectionHandshaker.DialRequestLatch] answer with plain strings — no device.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BroadcastDialConnectionHandshakerTest {

  private val action = BroadcastDialConnectionHandshaker.DEFAULT_DIAL_ACTION

  @Test
  fun `default dial action is wire-compatible with existing harnesses`() {
    // Harnesses and the desktop app broadcast this exact action; it survived the
    // xyz.block.echoapp package rename on purpose and must never change.
    assertThat(BroadcastDialConnectionHandshaker.DEFAULT_DIAL_ACTION)
        .isEqualTo("com.squareup.cash.ECHO_DIAL")
  }

  @Before
  fun setUp() {
    // The latch logs; the default logger goes to android.util.Log, which is not mocked here.
    EchoDebugLogger.install(StdOutEchoDebugLogger)
  }

  @Test
  fun `matching action with server_url dials that url`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://127.0.0.1:5000/echo",
        )
    assertThat(request).isEqualTo(ConnectionRequest(serverUrl = "ws://127.0.0.1:5000/echo"))
  }

  @Test
  fun `mismatched action is ignored`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = "com.example.SOMETHING_ELSE",
            expectedAction = action,
            serverUrl = "ws://127.0.0.1:5000/echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `null action is ignored`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = null,
            expectedAction = action,
            serverUrl = "ws://127.0.0.1:5000/echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `missing server_url is ignored`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = null,
        )
    assertThat(request).isNull()
  }

  @Test
  fun `blank server_url is ignored`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "   ",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `localhost ws url dials`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://localhost:5000/echo",
        )
    assertThat(request).isEqualTo(ConnectionRequest(serverUrl = "ws://localhost:5000/echo"))
  }

  @Test
  fun `ipv6 loopback ws url dials`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://[::1]:5000/echo",
        )
    assertThat(request).isEqualTo(ConnectionRequest(serverUrl = "ws://[::1]:5000/echo"))
  }

  @Test
  fun `uppercase ws scheme dials`() {
    // URI schemes are case-insensitive; a WS:// broadcast must not be rejected on scheme casing.
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "WS://127.0.0.1:5000/echo",
        )
    assertThat(request).isEqualTo(ConnectionRequest(serverUrl = "WS://127.0.0.1:5000/echo"))
  }

  @Test
  fun `off-device host is rejected`() {
    // The safety-critical case: an exported receiver must never dial an arbitrary remote host.
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://evil.example.com:5000/echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `loopback-lookalike host is rejected`() {
    // "127.0.0.1.evil.com" resolves off-device; a substring match on "127.0.0.1" must not pass it.
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://127.0.0.1.evil.com:5000/echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `wss scheme is rejected`() {
    // This loopback transport is plain ws; a wss:// (TLS) URL is not what the harness stands up.
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "wss://127.0.0.1:5000/echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `http scheme is rejected`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "http://127.0.0.1:5000/echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `malformed url is rejected without throwing`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://:::not a url",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `ws url with no host is rejected`() {
    // Well-formed ws:// but an empty authority parses to a null host — must be dropped, not dialed.
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws:///echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `out-of-range port is rejected`() {
    // java.net.URI parses port 99999 as loopback, but OkHttp rejects it and would throw at dial
    // time; validating with the same parser drops the typoed broadcast instead of crashing the
    // connect.
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://127.0.0.1:99999/echo",
        )
    assertThat(request).isNull()
  }

  @Test
  fun `max valid port dials`() {
    val request =
        BroadcastDialConnectionHandshaker.connectionRequestFor(
            action = action,
            expectedAction = action,
            serverUrl = "ws://127.0.0.1:65535/echo",
        )
    assertThat(request).isEqualTo(ConnectionRequest(serverUrl = "ws://127.0.0.1:65535/echo"))
  }

  @Test
  fun `request broadcast before collection is delivered when collection starts`() = runTest {
    // The case the latch exists for: the dial lands while EchoClient is between a stop() and the
    // next start(), so nothing is collecting yet. It must still be there when the client arms.
    val latch = newLatch()
    latch.onBroadcastReceived(action = action, serverUrl = "ws://127.0.0.1:5000/echo")

    assertThat(latch.nextRequest())
        .isEqualTo(ConnectionRequest(serverUrl = "ws://127.0.0.1:5000/echo"))
  }

  @Test
  fun `newest request wins`() = runTest {
    // A harness re-dialing while the client is down names a newer server each time; only the last
    // URL still has something listening on it.
    val latch = newLatch()
    latch.onBroadcastReceived(action = action, serverUrl = "ws://127.0.0.1:5000/echo")
    latch.onBroadcastReceived(action = action, serverUrl = "ws://127.0.0.1:5001/echo")

    assertThat(latch.nextRequest())
        .isEqualTo(ConnectionRequest(serverUrl = "ws://127.0.0.1:5001/echo"))
    assertThat(latch.nextRequest()).isNull()
  }

  @Test
  fun `request broadcast while collecting is delivered`() = runTest {
    val latch = newLatch()

    val request = async { latch.nextRequest() }
    runCurrent()
    latch.onBroadcastReceived(action = action, serverUrl = "ws://127.0.0.1:5000/echo")

    assertThat(request.await()).isEqualTo(ConnectionRequest(serverUrl = "ws://127.0.0.1:5000/echo"))
  }

  @Test
  fun `a latched request is delivered only once`() = runTest {
    // Delivery clears the latch, so an arm with no new broadcast waits for one instead of re-dialing
    // a URL that has already been handled.
    val latch = newLatch()
    latch.onBroadcastReceived(action = action, serverUrl = "ws://127.0.0.1:5000/echo")

    assertThat(latch.nextRequest())
        .isEqualTo(ConnectionRequest(serverUrl = "ws://127.0.0.1:5000/echo"))
    assertThat(latch.nextRequest()).isNull()
  }

  @Test
  fun `non-loopback request is not latched`() = runTest {
    val latch = newLatch()
    latch.onBroadcastReceived(action = action, serverUrl = "ws://evil.example.com:5000/echo")

    assertThat(latch.nextRequest()).isNull()
  }

  @Test
  fun `malformed request is not latched`() = runTest {
    val latch = newLatch()
    latch.onBroadcastReceived(action = action, serverUrl = "ws://:::not a url")
    latch.onBroadcastReceived(action = action, serverUrl = null)

    assertThat(latch.nextRequest()).isNull()
  }

  @Test
  fun `mismatched action is not latched`() = runTest {
    val latch = newLatch()
    latch.onBroadcastReceived(
        action = "com.example.SOMETHING_ELSE",
        serverUrl = "ws://127.0.0.1:5000/echo",
    )

    assertThat(latch.nextRequest()).isNull()
  }

  @Test
  fun `a rejected request does not clear a latched one`() = runTest {
    // An exported receiver hears everyone's broadcasts; a bogus one must not evict the harness's
    // pending dial.
    val latch = newLatch()
    latch.onBroadcastReceived(action = action, serverUrl = "ws://127.0.0.1:5000/echo")
    latch.onBroadcastReceived(action = action, serverUrl = "ws://evil.example.com:5000/echo")

    assertThat(latch.nextRequest())
        .isEqualTo(ConnectionRequest(serverUrl = "ws://127.0.0.1:5000/echo"))
  }

  private fun newLatch() = BroadcastDialConnectionHandshaker.DialRequestLatch(dialAction = action)

  /**
   * One arm of the client: collects a single request, or null when nothing is latched. The timeout
   * runs on `runTest`'s virtual clock, so "nothing is latched" resolves immediately rather than
   * waiting a real second.
   */
  private suspend fun BroadcastDialConnectionHandshaker.DialRequestLatch.nextRequest():
      ConnectionRequest? = withTimeoutOrNull(1.seconds) { requests().first() }
}
