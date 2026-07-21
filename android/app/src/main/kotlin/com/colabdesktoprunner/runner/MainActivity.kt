package com.colabdesktoprunner.runner

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.PowerManager
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
 * - قراءة حالة الجهاز (بطارية/شحن/توفير طاقة النظام/شبكة محدودة) لنظام
 *   توفير الطاقة الذكي — قراءة فقط، بلا أي أذونات إضافية.
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
                "getDeviceState" -> {
                    result.success(readDeviceState())
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * قراءة حالة الجهاز الحالية — لا تتطلب أي أذونات:
     * - batteryLevel: نسبة البطارية 0..100 (أو -1 إن تعذرت القراءة)
     * - isCharging: هل الجهاز يشحن
     * - systemPowerSave: هل وضع توفير الطاقة (Battery Saver) مفعّل
     * - isMeteredNetwork: هل الشبكة الحالية محدودة البيانات
     */
    private fun readDeviceState(): Map<String, Any> {
        var level = -1
        var charging = false
        try {
            val intent: Intent? = registerReceiver(
                null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            if (intent != null) {
                val raw = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                if (raw >= 0 && scale > 0) level = raw * 100 / scale
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
            }
        } catch (_: Exception) { /* قيم افتراضية آمنة */ }

        var powerSave = false
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerSave = pm.isPowerSaveMode
        } catch (_: Exception) { /* قيم افتراضية آمنة */ }

        var metered = false
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
            metered = caps != null &&
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (_: Exception) { /* قيم افتراضية آمنة */ }

        return mapOf(
            "batteryLevel" to level,
            "isCharging" to charging,
            "systemPowerSave" to powerSave,
            "isMeteredNetwork" to metered
        )
    }
}

