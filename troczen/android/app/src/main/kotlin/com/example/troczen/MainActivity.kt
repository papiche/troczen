package com.example.troczen

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.troczen/apk_path"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getApkPath") {
                try {
                    val appInfo = context.applicationInfo
                    val apkPath = appInfo.sourceDir
                    result.success(apkPath)
                } catch (e: Exception) {
                    result.error("UNAVAILABLE", "Apk path not available.", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
