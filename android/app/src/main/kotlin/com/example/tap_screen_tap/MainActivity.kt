package com.example.tap_screen_tap

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ClickerFlutterPlugin.registerWith(flutterEngine)
        scheduleOverlayEngineRegistration()
    }

    /// Overlay engine is created lazily; poll until it exists so island Start/Stop work.
    private fun scheduleOverlayEngineRegistration() {
        val handler = Handler(Looper.getMainLooper())
        var attempts = 0
        val runnable = object : Runnable {
            override fun run() {
                ClickerFlutterPlugin.registerOverlayEngineIfPresent()
                if (++attempts < 40) {
                    handler.postDelayed(this, 500)
                }
            }
        }
        handler.post(runnable)
    }
}
