package com.example.tap_screen_tap

import kotlinx.coroutines.CoroutineScope

object ClickerController {
    private var engine: ClickerEngine? = null

    fun attachService(service: ClickerAccessibilityService, scope: CoroutineScope) {
        engine = ClickerEngine(scope) { ClickerAccessibilityService.instance }
    }

    fun detachService() {
        engine?.stop()
        engine = null
    }

    fun startClicking(scriptMap: Map<String, Any?>, iterations: Int) {
        engine?.start(scriptMap, iterations) ?: run {
            ClickerEventSink.emit("error", mapOf("message" to "Accessibility service not available"))
        }
    }

    fun stopClicking() {
        engine?.stop()
    }

    fun isClicking(): Boolean = engine?.isClicking == true
}
