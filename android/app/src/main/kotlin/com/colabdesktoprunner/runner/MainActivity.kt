package com.colabdesktoprunner.runner

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
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
    private val eventsName = "com.almuhasab.colabdesktoprunner/device_events"

    // مستمعو أحداث النظام — تُسجّل مرة واحدة وتُلغى عند الإغلاق (لا تسريب).
    private var batteryReceiver: BroadcastReceiver? = null
    private var powerSaveReceiver: BroadcastReceiver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // قناة أحداث حالة الجهاز (بث فوري عند التغيّر — بدون polling)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventsName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
                registerSystemListeners()
            }

            override fun onCancel(args: Any?) {
                unregisterSystemListeners()
                eventSink = null
            }
        })
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
                "getInstalledApkPath" -> {
                    // مسار APK المثبّت الحالي — لقراءته وحساب SHA-256
                    // قبل تطبيق الرقعة التفاضلية (bspatch).
                    result.success(applicationInfo.sourceDir)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                    } else {
                        result.success(installApkWithPackageInstaller(path))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** إرسال حالة الجهاز الحالية لـ Flutter عبر قناة الأحداث (على الخيط الرئيسي). */
    private fun emitDeviceState() {
        val sink = eventSink ?: return
        val state = readDeviceState()
        mainHandler.post { sink.success(state) }
    }

    private fun registerSystemListeners() {
        if (batteryReceiver != null) return // مسجّلة مسبقًا — لا تكرار
        // تغيّر البطارية/الشحن (sticky broadcast — بلا أذونات)
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) = emitDeviceState()
        }
        registerReceiver(batteryReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_LOW)
            addAction(Intent.ACTION_BATTERY_OKAY)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        })
        // تغيّر وضع توفير طاقة النظام
        powerSaveReceiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) = emitDeviceState()
        }
        registerReceiver(
            powerSaveReceiver,
            IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        )
        // تغيّر الشبكة (محدودة/غير محدودة) عبر NetworkCallback
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = emitDeviceState()
                override fun onLost(network: Network) = emitDeviceState()
                override fun onCapabilitiesChanged(
                    network: Network, caps: NetworkCapabilities
                ) = emitDeviceState()
            }
            cm.registerDefaultNetworkCallback(networkCallback!!)
        } catch (_: Exception) { /* بدون مراقبة شبكة — يبقى refreshNow متاحًا */ }
        // حالة أولية فورية
        emitDeviceState()
    }

    private fun unregisterSystemListeners() {
        try { batteryReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        try { powerSaveReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        try {
            networkCallback?.let {
                (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                    .unregisterNetworkCallback(it)
            }
        } catch (_: Exception) {}
        batteryReceiver = null
        powerSaveReceiver = null
        networkCallback = null
    }

    override fun onDestroy() {
        unregisterSystemListeners()
        eventSink = null
        super.onDestroy()
    }

    /**
     * تثبيت APK محدّث عبر نافذة النظام الرسمية (ACTION_VIEW مع FileProvider).
     * - المستخدم يوافق بنفسه في نافذة النظام.
     * - أندرويد نفسه يتحقق من توقيع الشهادة (نفس الشهادة أو رفض)
     *   ويمنع أي Downgrade على مستوى النظام.
     */
    private fun installApkWithPackageInstaller(path: String): Boolean {
        return try {
            val file = java.io.File(path)
            if (!file.exists()) return false
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this, "$packageName.updates", file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
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

        // حالة الحرارة (Android 10+) — 0=NONE .. 6=SHUTDOWN، -1 عند عدم الدعم
        var thermal = -1
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                thermal = pm.currentThermalStatus
            }
        } catch (_: Exception) { /* قيم افتراضية آمنة */ }

        return mapOf(
            "batteryLevel" to level,
            "isCharging" to charging,
            "systemPowerSave" to powerSave,
            "isMeteredNetwork" to metered,
            "thermalStatus" to thermal
        )
    }
}

