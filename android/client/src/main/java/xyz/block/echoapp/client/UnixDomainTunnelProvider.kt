package xyz.block.echoapp.client

import android.net.LocalSocket

/**
 * Provides access to an accepted [LocalSocket] that should be reused as a tunnel for subsequent
 * OkHttp traffic. The consumer becomes responsible for closing the socket when finished.
 */
interface UnixDomainTunnelProvider {
  fun consumeAcceptedLocalSocket(): LocalSocket?
}
