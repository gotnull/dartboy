package com.example.dartboy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build

class MainActivity: FlutterActivity() {
    private val DEVICE_INFO_CHANNEL = "flutter.dev/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "getAndroidApiLevel" -> {
                    val apiLevel = Build.VERSION.SDK_INT
                    result.success(apiLevel)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}