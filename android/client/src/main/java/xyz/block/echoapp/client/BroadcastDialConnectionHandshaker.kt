package xyz.block.echoapp.client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import xyz.block.echoapp.client.internal.ConnectionHandshaker
import xyz.block.echoapp.plugin.utils.EchoDebugLogger
import java.io.Closeable
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * A [ConnectionHandshaker] that stays dormant until it receives an out-of-band **dial-in** broadcast
 * naming a WebSocket URL, then tells [EchoClient] to dial that URL.
 *
 * This is the host-less, on-device capture transport. The usual handshakers ([RealNsdAdvertiser],
 * [UnixDomainSocketServer]) make the app *discoverable* and wait for a desktop/host to connect **to**
 * the device. On a host-less CI test farm there is no such host, and connecting *to* the app's socket
 * from another on-device process is denied by SELinux. This inverts the transport: a test harness
 * stands up a loopback WebSocket **server** on the device and broadcasts its `ws://127.0.0.1:<port>`
 * URL; this handshaker hands that URL to [EchoClient], which **dials out** to it. A plain loopback TCP
 * connection crosses no SELinux boundary, so it works where the advertise-and-wait path cannot.
 *
 * Because this is not a [UnixDomainSocketServer], [EchoClient] dials the received URL verbatim (no
 * localhost/tunnel rewrite). Pair it with a plain [okhttp3.OkHttpClient] — no
 * [xyz.block.echoapp.client.transport.TunnelSocketFactory] — since the loopback dial is ordinary
 * TCP.
 *
 * ### Lifetime and latching
 *
 * The receiver is registered in [attach], for this handshaker's lifetime, rather than only while
 * [startReceivingConnectionRequest] is collected. [EchoClient] consumes a single request per
 * [EchoClient.start], so a harness that captures more than once has to restart the client between
 * rounds; a receiver that existed only while collecting meant a dial landing between a `stop()` and
 * the next `start()` reached nothing and was dropped by Android with no replay. Instead the receiver
 * runs the whole time and the newest valid request is **latched**, so a dial sent before the client
 * arms is still dialed once it does — the harness no longer has to time its broadcast or sleep a
 * grace period.
 *
 * The latch holds one request: a second dial arriving before the first is consumed replaces it, since
 * the newest URL is the one the harness is listening on. A latched request is cleared when it is
 * handed to a collector, so each broadcast causes at most one dial. It does **not** expire on a
 * timer. A request that has been latched a while names a port that may be gone, but dialing a dead
 * port fails harmlessly and the harness re-dials, whereas a staleness bound needs a clock and can
 * drop a legitimate dial sent to an app that was slow to start. Clearing on delivery — rather than
 * replaying the newest request to every arm — matters because [EchoClient] restarts itself when the
 * socket closes: an un-cleared latch would make each of those restarts re-dial the URL it just
 * finished with, and a failed dial leaves the client's connection job parked until the next `stop()`.
 *
 * [stopReceivingConnectionRequest] is therefore a no-op — it runs on every disconnect, and either
 * unregistering or clearing the latch there would reopen the window this latch exists to close. Call
 * [close] to unregister the receiver.
 *
 * ### Safety / gating
 *
 * Constructing this handshaker reaches out nowhere, and attaching it only starts *listening*: a
 * latched URL is dialed when [EchoClient.start] arms the client, so an app that embeds this but is
 * never sent the broadcast dials nothing. Echo is already embedded only in debug/internal builds of
 * its host apps, which this preserves.
 *
 * The receiver is registered [ContextCompat.RECEIVER_EXPORTED] so an `am broadcast` from the adb
 * shell — a different UID, the test-harness trigger — reaches it on API 33+. Because it is exported,
 * any app on the device can send this broadcast, so the URL it names is **validated before use**:
 * only a loopback `ws://` URL (host `127.0.0.1`, `::1`, or `localhost`) is accepted (see
 * [connectionRequestFor]). A broadcast naming an off-device host — malicious or a typo — is dropped,
 * so this transport can never be coerced into streaming Echo traffic anywhere but a capture server on
 * the same device.
 *
 * Loopback validation bounds *where* traffic can go (on-device only) but does **not authenticate who
 * owns the loopback listener**: the broadcast is unauthenticated, so on a device that also has an
 * untrusted app installed, that app could stand up its own loopback WebSocket, send [dialAction] with
 * its port, and receive the Echo plugin payloads. This is an accepted limitation of this
 * **debug/internal-only, opt-in diagnostic** transport — Echo ships in no production build, capture
 * runs on test devices (never against real user data), and the receiver must be explicitly wired in.
 * Authenticating the sender (a `broadcastPermission` naming a shell-held, app-unobtainable permission,
 * or a shared token co-provisioned with the harness) is a tracked follow-up; both candidates need
 * on-device validation that they don't break the adb-shell trigger this transport depends on.
 *
 * @param context used to register/unregister the [BroadcastReceiver]; its application context is what
 *   actually holds the registration, since the receiver outlives any Activity.
 * @param dialAction the broadcast action to listen for; must match the harness's trigger.
 */
class BroadcastDialConnectionHandshaker
@JvmOverloads
constructor(
    context: Context,
    private val dialAction: String = DEFAULT_DIAL_ACTION,
) : ConnectionHandshaker, Closeable {

  /**
   * The receiver outlives any single connection, so it is registered against the application rather
   * than whatever [Context] the caller passed: registering a process-lifetime receiver on an Activity
   * leaks it (and the Activity) the moment that Activity is destroyed or rotated.
   */
  private val context: Context = context.applicationContext ?: context

  private val latch = DialRequestLatch(dialAction)

  private val receiver =
      object : BroadcastReceiver() {
        override fun onReceive(
            context: Context?,
            intent: Intent?,
        ) {
          latch.onBroadcastReceived(
              action = intent?.action,
              serverUrl = intent?.getStringExtra(SERVER_URL_EXTRA),
          )
        }
      }

  /**
   * Guards against registering twice (and against unregistering a receiver that isn't up). Guarded by
   * the monitor [attach] and [close] hold, so the flag can't disagree with what is actually
   * registered.
   */
  private var isRegistered = false

  /**
   * Registers the dial receiver for the rest of this handshaker's life, so requests are latched even
   * while [EchoClient] is between a `stop()` and a `start()`. Idempotent: attaching the same
   * handshaker to a second client registers nothing further, so no receiver is leaked.
   */
  @Synchronized
  override fun attach(client: EchoClient) {
    if (isRegistered) return
    ContextCompat.registerReceiver(
        context,
        receiver,
        IntentFilter(dialAction),
        ContextCompat.RECEIVER_EXPORTED,
    )
    isRegistered = true
    EchoDebugLogger.debug(TAG, "Listening for dial-in broadcast '$dialAction'")
  }

  override suspend fun startReceivingConnectionRequest(): Flow<ConnectionRequest?> = latch.requests()

  /**
   * Deliberately a no-op. [EchoClient] calls this on every disconnect; tearing the receiver down or
   * dropping the latched request here would lose a dial sent while the client is restarting, which is
   * exactly the case the latch exists for. [close] releases the receiver.
   */
  override fun stopReceivingConnectionRequest() = Unit

  /**
   * Unregisters the dial receiver. Idempotent, and safe to call whether or not [attach] ran. Any
   * latched-but-unconsumed request is kept, so re-attaching resumes where this left off.
   */
  @Synchronized
  override fun close() {
    if (!isRegistered) return
    isRegistered = false
    runCatching { context.unregisterReceiver(receiver) }
    EchoDebugLogger.debug(TAG, "Stopped listening for dial-in broadcast '$dialAction'")
  }

  /**
   * Holds the newest valid dial request until something collects it, decoupling *when the broadcast
   * arrives* from *when [EchoClient] arms*. Backed by a conflated [Channel]: a request sent with no
   * collector is buffered rather than dropped, a newer one replaces it, and receiving consumes it (so
   * an arm with nothing new pending waits instead of re-dialing a spent URL).
   *
   * Holds no [Context] and touches no Android API, so the latch — and the validation that feeds it —
   * is unit-testable without a device or a live [BroadcastReceiver].
   */
  internal class DialRequestLatch(private val dialAction: String) {
    private val pending = Channel<ConnectionRequest>(capacity = Channel.CONFLATED)

    /** Feeds a received broadcast in; invalid ones are dropped and do not disturb the latch. */
    fun onBroadcastReceived(
        action: String?,
        serverUrl: String?,
    ) {
      val request =
          connectionRequestFor(
              action = action,
              expectedAction = dialAction,
              serverUrl = serverUrl,
          )
      if (request == null) {
        EchoDebugLogger.warn(
            TAG,
            "Ignoring broadcast $action: '$SERVER_URL_EXTRA' is missing or not a " +
                "loopback ws:// URL (got: $serverUrl)",
        )
        return
      }
      EchoDebugLogger.debug(TAG, "Dial-in broadcast received; will dial ${request.serverUrl}")
      pending.trySend(request)
    }

    /** Emits latched and subsequent requests, one to one collector each. */
    fun requests(): Flow<ConnectionRequest?> = pending.receiveAsFlow()
  }

  companion object {
    private const val TAG = "BroadcastDialHandshaker"

    /** Default broadcast action a harness sends to trigger a dial-in. */
    const val DEFAULT_DIAL_ACTION = "com.squareup.cash.ECHO_DIAL"

    /** String extra carrying the `ws://…` URL to dial; mirrors [ConnectionRequest.serverUrl]. */
    const val SERVER_URL_EXTRA = "server_url"

    /** Hosts a dial URL may name; anything else is off-device and rejected. */
    private val LOOPBACK_HOSTS = setOf("127.0.0.1", "::1", "localhost")

    /**
     * Pure mapping from a received broadcast's [action] + [serverUrl] extra to a [ConnectionRequest]:
     * returns one only when [action] matches [expectedAction] and [serverUrl] is a valid **loopback**
     * `ws://` URL. The receiver is exported (any app on the device can send the broadcast), so a URL
     * that isn't loopback — or isn't a well-formed `ws://` URL at all — is dropped here rather than
     * handed to [EchoClient], which would otherwise dial an arbitrary host or throw on a malformed
     * value. Takes plain strings (not an [Intent]) so the dial decision is unit-testable with no
     * device and no live [BroadcastReceiver].
     */
    internal fun connectionRequestFor(
        action: String?,
        expectedAction: String,
        serverUrl: String?,
    ): ConnectionRequest? {
      if (action != expectedAction) return null
      if (serverUrl.isNullOrBlank()) return null
      if (!isLoopbackWebSocketUrl(serverUrl)) return null
      return ConnectionRequest(serverUrl = serverUrl)
    }

    /**
     * True only for a `ws://` URL whose host is a loopback literal, validated with the **same parser
     * OkHttp dials with** so there is no parser differential. [EchoClient] hands the URL to
     * `Request.Builder.url(...)`, which maps a `ws://` scheme to `http://` and parses with
     * [okhttp3.HttpUrl]; that parser enforces host well-formedness and a `1..65535` port range that
     * [java.net.URI] does not — e.g. `URI` happily parses `ws://127.0.0.1:99999`, which then throws in
     * OkHttp and cancels the connect. Mirroring OkHttp's `ws://`→`http://` rewrite and reusing its
     * parser here guarantees anything this accepts, OkHttp can actually dial. Non-`ws` schemes
     * (`wss`, `http`, …) are rejected — this loopback transport is plain `ws` (see the class doc).
     */
    private fun isLoopbackWebSocketUrl(serverUrl: String): Boolean {
      if (!serverUrl.startsWith("ws:", ignoreCase = true)) return false
      // OkHttp's Request.Builder.url() replaces a leading "ws:" with "http:" before parsing (HttpUrl
      // only accepts http/https). Do the same so HttpUrl validates the exact string OkHttp will dial.
      val httpUrl = ("http:" + serverUrl.substring("ws:".length)).toHttpUrlOrNull() ?: return false
      // HttpUrl.host is already canonicalized + lowercased (IPv6 without brackets, e.g. "::1").
      return httpUrl.host in LOOPBACK_HOSTS
    }
  }
}
