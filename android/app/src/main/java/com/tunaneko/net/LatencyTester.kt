package com.tunaneko.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Semaphore

object LatencyTester {
    private const val TIMEOUT_MS = 2000

    /** TCP connect time to host:443 in ms, or null if unreachable. */
    suspend fun measure(host: String): Int? = kotlinx.coroutines.withContext(Dispatchers.IO) {
        withTimeoutOrNull(TIMEOUT_MS.toLong()) {
            try {
                val start = System.nanoTime()
                Socket().use { it.connect(InetSocketAddress(host, 443), TIMEOUT_MS) }
                ((System.nanoTime() - start) / 1_000_000).toInt()
            } catch (e: Exception) {
                null
            }
        }
    }

    /** Measure many hosts with bounded concurrency; calls back per result. */
    suspend fun measureAll(
        targets: List<Pair<String, String>>,   // id to host
        concurrency: Int = 32,
        onResult: (String, Int?) -> Unit
    ) = coroutineScope {
        val sem = Semaphore(concurrency)
        targets.map { (id, host) ->
            async(Dispatchers.IO) {
                sem.acquire()
                try {
                    onResult(id, measure(host))
                } finally {
                    sem.release()
                }
            }
        }.forEach { it.await() }
    }
}
