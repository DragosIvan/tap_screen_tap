package com.example.tap_screen_tap

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager

/**
 * Shows a short-lived ripple at screen coordinates while a script runs.
 * Uses [TYPE_ACCESSIBILITY_OVERLAY] so no extra overlay permission is needed.
 */
object TapRippleOverlay {
    private const val MAX_RADIUS_PX = 30f
    private const val STROKE_WIDTH_PX = 2f

    private val mainHandler = Handler(Looper.getMainLooper())

    fun show(service: AccessibilityService, x: Float, y: Float) {
        mainHandler.post { showOnMainThread(service, x, y) }
    }

    private fun showOnMainThread(service: AccessibilityService, x: Float, y: Float) {
        val windowManager = service.getSystemService(WindowManager::class.java) ?: return
        val padding = (MAX_RADIUS_PX + STROKE_WIDTH_PX).toInt()
        val size = padding * 2

        lateinit var ripple: TapRippleView
        ripple = TapRippleView(
            context = service,
            maxRadiusPx = MAX_RADIUS_PX,
            strokeWidthPx = STROKE_WIDTH_PX,
            onFinished = {
                mainHandler.post {
                    try {
                        windowManager.removeView(ripple)
                    } catch (_: Exception) {
                    }
                }
            },
        )

        val params = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = (x - padding).toInt()
            this.y = (y - padding).toInt()
        }

        try {
            windowManager.addView(ripple, params)
        } catch (_: Exception) {
        }
    }
}
