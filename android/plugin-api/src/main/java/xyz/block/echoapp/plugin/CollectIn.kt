package xyz.block.echoapp.plugin

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

inline fun <reified T> Flow<T>.collectIn(
    scope: CoroutineScope,
    noinline collector: suspend (T) -> Unit,
): Job {
  return scope.launch { collect(collector) }
}

inline fun <reified T> Flow<T>.collectLatestIn(
    scope: CoroutineScope,
    noinline collector: suspend (T) -> Unit,
): Job {
  return scope.launch { collectLatest(collector) }
}
