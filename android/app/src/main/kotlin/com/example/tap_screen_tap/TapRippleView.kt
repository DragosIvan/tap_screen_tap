package com.example.tap_screen_tap

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import android.view.animation.DecelerateInterpolator

/**
 * Animated circle: transparent fill, 2px red stroke, radius 0 → [maxRadiusPx].
 */
class TapRippleView(
    context: Context,
    private val maxRadiusPx: Float,
    private val strokeWidthPx: Float,
    private val onFinished: () -> Unit,
) : View(context) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = strokeWidthPx
        color = Color.RED
    }

    private var radius = 0f

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        ValueAnimator.ofFloat(0f, maxRadiusPx).apply {
            duration = 560L
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                radius = animator.animatedValue as Float
                invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    onFinished()
                }
            })
            start()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        canvas.drawCircle(cx, cy, radius, paint)
    }
}
