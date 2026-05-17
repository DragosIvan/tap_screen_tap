package com.example.tap_screen_tap

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ClickerFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        registerChannels(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        when (call.method) {
            "isAccessibilityEnabled" -> result.success(ctx != null && isAccessibilityServiceEnabled(ctx))
            "openAccessibilitySettings" -> {
                ctx?.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "canDrawOverlays" -> result.success(ctx != null && Settings.canDrawOverlays(ctx))
            "openOverlaySettings" -> {
                if (ctx != null) {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${ctx.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    ctx.startActivity(intent)
                }
                result.success(null)
            }
            "startClicking" -> {
                @Suppress("UNCHECKED_CAST")
                val script = call.argument<Map<String, Any?>>("script")
                val iterations = call.argument<Int>("iterations") ?: -1
                if (script == null) {
                    result.error("INVALID_ARGS", "script is required", null)
                } else {
                    ClickerController.startClicking(script, iterations)
                    result.success(null)
                }
            }
            "stopClicking" -> {
                ClickerController.stopClicking()
                result.success(null)
            }
            "isClicking" -> result.success(ClickerController.isClicking())
            "ensureOverlayEngineRegistered" -> {
                registerOverlayEngineIfPresent()
                result.success(null)
            }
            "notifyRecorderDone" -> {
                // Called from the overlay isolate after steps are saved.
                // Emitting via ClickerEventSink reaches the main engine's EventChannel
                // without going through the overlay messenger (which is torn down during
                // the overlay close/reopen cycle).
                ClickerEventSink.emit("recorderDone", emptyMap<String, Any>())
                result.success(null)
            }
            "getDisplayMetrics" -> {
                val dm = ctx!!.resources.displayMetrics
                result.success(
                    mapOf(
                        "widthPx" to dm.widthPixels,
                        "heightPx" to dm.heightPixels,
                        "density" to dm.density.toDouble(),
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun registerChannels(messenger: io.flutter.plugin.common.BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                private var eventSink: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    ClickerEventSink.addSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    ClickerEventSink.removeSink(eventSink)
                    eventSink = null
                }
            })
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "com.example.tap_screen_tap/clicker"
        private const val EVENT_CHANNEL = "com.example.tap_screen_tap/clicker_events"
        private const val OVERLAY_ENGINE_ID = "myCachedEngine"

        private val registeredEngines = mutableSetOf<FlutterEngine>()

        fun registerWith(engine: FlutterEngine) {
            if (!registeredEngines.add(engine)) return
            if (engine.plugins.has(ClickerFlutterPlugin::class.java)) return
            engine.plugins.add(ClickerFlutterPlugin())
        }

        fun registerOverlayEngineIfPresent() {
            val engine = io.flutter.embedding.engine.FlutterEngineCache
                .getInstance()
                .get(OVERLAY_ENGINE_ID)
                ?: return
            registerWith(engine)
        }

        private fun isAccessibilityServiceEnabled(context: Context): Boolean {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            val enabled = am.getEnabledAccessibilityServiceList(
                AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
            )
            val expectedId =
                "${context.packageName}/${ClickerAccessibilityService::class.java.canonicalName}"
            for (service in enabled) {
                val id = service.id
                if (id == expectedId ||
                    id.endsWith("/${ClickerAccessibilityService::class.java.simpleName}")
                ) {
                    return true
                }
            }
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServices)
            while (colonSplitter.hasNext()) {
                val componentName = colonSplitter.next()
                if (componentName.contains(context.packageName) &&
                    componentName.contains("ClickerAccessibilityService")
                ) {
                    return true
                }
            }
            return false
        }
    }
}
