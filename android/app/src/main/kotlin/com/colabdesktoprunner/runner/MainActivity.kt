package com.colabdesktoprunner.runner

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity - Colab Desktop Runner
 *
 * طبقة Kotlin أصلية توفر:
 * - قناة MethodChannel لتفعيل/تعطيل FLAG_KEEP_SCREEN_ON (إبقاء الشاشة مضاءة
 *   أثناء جلسة سطح المكتب) بشكل آمن وتحت تحكم المستخدم فقط.
 *
 * ملاحظات أمنية:
 * - لا يوجد أي AccessibilityService.
 * - لا يوجد أي اعتراض لبيانات تسجيل الدخول أو Cookies.
 * - لا يتم تسجيل أي بيانات حساسة في Logcat.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.almuhasab.colabdesktoprunner/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}

