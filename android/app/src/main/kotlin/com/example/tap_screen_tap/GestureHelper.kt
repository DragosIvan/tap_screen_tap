package com.example.tap_screen_tap

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.util.DisplayMetrics
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

object GestureHelper {
    private const val TAP_DURATION_MS = 50L

    /** True when stored coords are overlay logical (pre-fix), not physical pixels. */
    fun scriptUsesLegacyLogicalCoords(
        metrics: DisplayMetrics,
        steps: List<ClickerEngine.StepConfig>,
    ): Boolean {
        if (steps.isEmpty()) return false
        val logicalW = metrics.widthPixels / metrics.density
        val logicalH = metrics.heightPixels / metrics.density
        return steps.all { it.x <= logicalW * 1.02f && it.y <= logicalH * 1.02f }
    }

    fun stepToPhysical(
        metrics: DisplayMetrics,
        step: ClickerEngine.StepConfig,
        legacy: Boolean,
    ): ClickerEngine.StepConfig {
        if (!legacy) return step
        return step.copy(
            x = step.x * metrics.density,
            y = step.y * metrics.density,
        )
    }

    suspend fun dispatchTap(service: AccessibilityService, x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, TAP_DURATION_MS)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return suspendCoroutine { continuation ->
            service.dispatchGesture(
                gesture,
                object : AccessibilityService.GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        continuation.resume(true)
                    }

                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        continuation.resume(false)
                    }
                },
                null,
            )
        }
    }
}
