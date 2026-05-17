package com.example.tap_screen_tap

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object ClickerEventSink {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sinks = mutableSetOf<EventChannel.EventSink>()

    fun addSink(sink: EventChannel.EventSink?) {
        if (sink != null) sinks.add(sink)
    }

    fun removeSink(sink: EventChannel.EventSink?) {
        if (sink != null) sinks.remove(sink)
    }

    fun emit(event: String, data: Map<String, Any?>) {
        val payload = HashMap<String, Any?>(data)
        payload["event"] = event
        mainHandler.post {
            for (sink in sinks.toList()) {
                sink.success(payload)
            }
        }
    }
}
