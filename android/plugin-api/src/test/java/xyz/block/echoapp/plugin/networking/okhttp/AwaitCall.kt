package xyz.block.echoapp.plugin.networking.okhttp

import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response
import okio.IOException

/** A test utility to make OkHttp calls suspending. */
internal suspend fun Call.await(): Response {
  return suspendCancellableCoroutine { continuation ->
    enqueue(
        object : Callback {
          override fun onResponse(
              call: Call,
              response: Response,
          ) {
            if (continuation.isCancelled) return
            continuation.resume(response)
          }

          override fun onFailure(
              call: Call,
              e: IOException,
          ) {
            if (continuation.isCancelled) return
            continuation.resumeWithException(e)
          }
        })
    continuation.invokeOnCancellation {
      try {
        this@await.cancel()
      } catch (_: Throwable) {}
    }
  }
}
