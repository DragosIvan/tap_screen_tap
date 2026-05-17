package com.example.tap_screen_tap

import android.accessibilityservice.AccessibilityService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

class ClickerEngine(
    private val scope: CoroutineScope,
    private val getService: () -> ClickerAccessibilityService?,
) {
    private var job: Job? = null

    @Volatile
    var isClicking: Boolean = false
        private set

    fun start(scriptMap: Map<String, Any?>, iterations: Int) {
        stop()
        val service = getService()
        if (service == null) {
            ClickerEventSink.emit("error", mapOf("message" to "Accessibility service not connected"))
            return
        }

        val script = ScriptConfig.fromMap(scriptMap)
        isClicking = true
        ClickerEventSink.emit("clickingStateChanged", mapOf("isClicking" to true))

        job = scope.launch(Dispatchers.Default) {
            runScript(service, script, iterations)
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        if (isClicking) {
            isClicking = false
            ClickerEventSink.emit("clickingStateChanged", mapOf("isClicking" to false))
        }
    }

    private suspend fun runScript(
        service: AccessibilityService,
        script: ScriptConfig,
        iterationsRequested: Int,
    ) {
        val runStartMs = System.currentTimeMillis()
        var iterationsCompleted = 0
        var totalTaps = 0
        var stopReason = "user_stopped"

        emitLog(script.id, "runStarted", mapOf(
            "scriptName" to script.name,
            "iterationsRequested" to iterationsRequested,
            "stepCount" to script.steps.size,
        ))

        val displayMetrics = service.resources.displayMetrics
        val legacyLogicalCoords = GestureHelper.scriptUsesLegacyLogicalCoords(
            displayMetrics,
            script.steps,
        )

        try {
            while (currentCoroutineContext().isActive) {
                if (iterationsRequested >= 0 && iterationsCompleted >= iterationsRequested) {
                    stopReason = "iterations_done"
                    break
                }

                emitLog(script.id, "iterationStarted", mapOf(
                    "iteration" to iterationsCompleted + 1,
                ))

                for ((index, step) in script.steps.withIndex()) {
                    if (!currentCoroutineContext().isActive) break

                    val stepPx = GestureHelper.stepToPhysical(
                        displayMetrics,
                        step,
                        legacyLogicalCoords,
                    )
                    val coords = resolveTapCoords(script, stepPx)
                    val actualX = coords.x
                    val actualY = coords.y
                    val jitterApplied = coords.jitterApplied
                    val radiusUsed = coords.radiusUsed
                    val tapOk = GestureHelper.dispatchTap(service, actualX, actualY)
                    totalTaps++
                    if (tapOk) {
                        TapRippleOverlay.show(service, actualX, actualY)
                    }

                    emitLog(script.id, "tapPerformed", mapOf(
                        "stepIndex" to index,
                        "definedX" to step.x,
                        "definedY" to step.y,
                        "actualX" to actualX,
                        "actualY" to actualY,
                        "radiusPx" to radiusUsed,
                        "jitterApplied" to jitterApplied,
                        "gestureSuccess" to tapOk,
                    ))

                    if (!tapOk) {
                        stopReason = "error"
                        emitLog(script.id, "error", mapOf(
                            "message" to "Gesture dispatch failed",
                            "stepIndex" to index,
                        ))
                        return
                    }

                    // Wait after every step, including the last one in the iteration.
                    // Previously we only delayed when index < lastIndex, so single-step
                    // scripts never applied per-step or global-random delays.
                    val delayInfo = computeDelay(script, step)
                    if (delayInfo.totalMs > 0) {
                        emitLog(script.id, "delayApplied", mapOf(
                            "stepIndex" to index,
                            "baseDelayMs" to delayInfo.baseMs,
                            "randomAddonMs" to delayInfo.randomAddonMs,
                            "totalDelayMs" to delayInfo.totalMs,
                            "source" to delayInfo.source,
                        ))
                        delay(delayInfo.totalMs)
                    }
                }

                if (!currentCoroutineContext().isActive) break

                if (script.endDelayMs > 0) {
                    emitLog(script.id, "delayApplied", mapOf(
                        "stepIndex" to -1,
                        "baseDelayMs" to script.endDelayMs,
                        "randomAddonMs" to 0,
                        "totalDelayMs" to script.endDelayMs,
                        "source" to "endDelay",
                    ))
                    delay(script.endDelayMs.toLong())
                }

                iterationsCompleted++
                ClickerEventSink.emit("iterationCompleted", mapOf("iteration" to iterationsCompleted))

                emitLog(script.id, "iterationCompleted", mapOf(
                    "iteration" to iterationsCompleted,
                ))

                if (iterationsRequested >= 0 && iterationsCompleted >= iterationsRequested) {
                    stopReason = "iterations_done"
                    break
                }
            }

            if (stopReason != "iterations_done" && stopReason != "error") {
                stopReason = if (iterationsRequested < 0) "user_stopped" else stopReason
            }
        } catch (_: CancellationException) {
            stopReason = "user_stopped"
        } finally {
            val durationMs = System.currentTimeMillis() - runStartMs
            emitLog(script.id, "runEnded", mapOf(
                "totalTaps" to totalTaps,
                "totalDurationMs" to durationMs,
                "stopReason" to stopReason,
                "iterationsCompleted" to iterationsCompleted,
                "iterationsRequested" to iterationsRequested,
            ))
            isClicking = false
            ClickerEventSink.emit("clickingStateChanged", mapOf("isClicking" to false))
        }
    }

    private fun emitLog(scriptId: String, type: String, fields: Map<String, Any?>) {
        val entry = HashMap<String, Any?>(fields)
        entry["type"] = type
        entry["timestamp"] = System.currentTimeMillis()
        ClickerEventSink.emit("logEvent", mapOf(
            "scriptId" to scriptId,
            "entry" to entry,
        ))
    }

    private data class DelayInfo(
        val baseMs: Int,
        val randomAddonMs: Int,
        val totalMs: Long,
        val source: String,
    )

    private fun computeDelay(script: ScriptConfig, step: StepConfig): DelayInfo {
        val baseMs: Int
        val source: String
        if (step.delayAfterMs != null) {
            baseMs = step.delayAfterMs
            source = "perStep"
        } else {
            baseMs = if (script.defaultMinDelayMs >= script.defaultMaxDelayMs) {
                script.defaultMinDelayMs
            } else {
                Random.nextInt(script.defaultMinDelayMs, script.defaultMaxDelayMs + 1)
            }
            source = "defaultRange"
        }
        val randomAddonMs = if (script.globalRandomDelayEnabled && script.globalMaxRandomDelaySec > 0) {
            Random.nextInt(0, script.globalMaxRandomDelaySec * 1000 + 1)
        } else {
            0
        }
        return DelayInfo(baseMs, randomAddonMs, (baseMs + randomAddonMs).toLong(), source)
    }

    private fun resolveTapCoords(
        script: ScriptConfig,
        step: StepConfig,
    ): TapCoords {
        if (!script.tapRandomnessEnabled) {
            return TapCoords(step.x, step.y, false, 0)
        }
        val radius = step.radiusPx ?: script.globalRadiusPx
        if (radius <= 0) {
            return TapCoords(step.x, step.y, false, 0)
        }
        val u = Random.nextDouble()
        val v = Random.nextDouble()
        val r = radius * sqrt(u)
        val theta = 2 * Math.PI * v
        val dx = (r * cos(theta)).toFloat()
        val dy = (r * sin(theta)).toFloat()
        return TapCoords(step.x + dx, step.y + dy, true, radius)
    }

    private data class TapCoords(
        val x: Float,
        val y: Float,
        val jitterApplied: Boolean,
        val radiusUsed: Int,
    )

    data class ScriptConfig(
        val id: String,
        val name: String,
        val steps: List<StepConfig>,
        val tapRandomnessEnabled: Boolean,
        val globalRadiusPx: Int,
        val defaultMinDelayMs: Int,
        val defaultMaxDelayMs: Int,
        val globalRandomDelayEnabled: Boolean,
        val globalMaxRandomDelaySec: Int,
        val endDelayMs: Int,
    ) {
        companion object {
            @Suppress("UNCHECKED_CAST")
            fun fromMap(map: Map<String, Any?>): ScriptConfig {
                val stepsRaw = map["steps"] as? List<*> ?: emptyList<Any>()
                val steps = stepsRaw.mapNotNull { item ->
                    val m = item as? Map<String, Any?> ?: return@mapNotNull null
                    StepConfig(
                        x = (m["x"] as? Number)?.toFloat() ?: 0f,
                        y = (m["y"] as? Number)?.toFloat() ?: 0f,
                        delayAfterMs = (m["delayAfterMs"] as? Number)?.toInt(),
                        radiusPx = (m["radiusPx"] as? Number)?.toInt(),
                    )
                }
                return ScriptConfig(
                    id = map["id"] as? String ?: "",
                    name = map["name"] as? String ?: "Script",
                    steps = steps,
                    tapRandomnessEnabled = map["tapRandomnessEnabled"] as? Boolean ?: false,
                    globalRadiusPx = (map["globalRadiusPx"] as? Number)?.toInt() ?: 15,
                    defaultMinDelayMs = (map["defaultMinDelayMs"] as? Number)?.toInt() ?: 1000,
                    defaultMaxDelayMs = (map["defaultMaxDelayMs"] as? Number)?.toInt() ?: 3000,
                    globalRandomDelayEnabled = map["globalRandomDelayEnabled"] as? Boolean ?: false,
                    globalMaxRandomDelaySec = (map["globalMaxRandomDelaySec"] as? Number)?.toInt() ?: 0,
                    endDelayMs = (map["endDelayMs"] as? Number)?.toInt() ?: 0,
                )
            }
        }
    }

    data class StepConfig(
        val x: Float,
        val y: Float,
        val delayAfterMs: Int? = null,
        val radiusPx: Int? = null,
    )
}
