package com.example.tap_screen_tap

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class ClickerAccessibilityService : AccessibilityService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        ClickerController.attachService(this, serviceScope)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op: we only need gesture dispatch capability.
    }

    override fun onInterrupt() {
        ClickerController.stopClicking()
    }

    override fun onDestroy() {
        ClickerController.detachService()
        serviceScope.cancel()
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    companion object {
        @Volatile
        var instance: ClickerAccessibilityService? = null
            private set
    }
}
