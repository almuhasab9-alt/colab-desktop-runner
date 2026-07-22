import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/power_policy.dart';
import 'settings_service.dart';

/// خدمة الطاقة المركزية.
///
/// - مصدر الحقيقة الوحيد لسياسة الطاقة الحالية ([policy]).
/// - تقرأ حالة الجهاز من طبقة Kotlin (بطارية/شحن/توفير طاقة/شبكة محدودة)
///   عبر MethodChannel — بلا أي أذونات إضافية.
/// - تتتبع دورة حياة التطبيق: في الخلفية تتوقف كل عمليات التحديث الدورية
///   (احترام Doze / App Standby — لا WakeLocks ولا خدمات أمامية).
/// - كل مستهلكي الطاقة (مؤقتات إعادة الاتصال، إبقاء الشاشة، الرسوم)
///   يقرؤون من هذه الخدمة ولا يقررون بأنفسهم.
class PowerService extends ChangeNotifier with WidgetsBindingObserver {
  static const _channel =
      MethodChannel('com.almuhasab.colabdesktoprunner/native');
  static const _eventsChannel =
      EventChannel('com.almuhasab.colabdesktoprunner/device_events');

  final SettingsService _settings;
  DeviceStateSnapshot _deviceState = const DeviceStateSnapshot();
  PowerPolicy _policy;
  bool _isBackground = false;
  StreamSubscription<dynamic>? _eventsSub;
  Timer? _debounce;

  /// بلا polling إطلاقًا — التحديث يتم عبر:
  /// 1) أحداث النظام الفورية (بطارية/شحن/توفير طاقة/شبكة/حرارة)
  ///    من Kotlin عبر EventChannel مع debounce 500ms.
  /// 2) الإنشاء والعودة للمقدمة وrefreshNow.
  PowerService(this._settings)
      : _policy = PowerPolicyEngine.compute(
          PowerPolicyEngine.parseMode(_settings.powerMode),
          const DeviceStateSnapshot(),
        ) {
    WidgetsBinding.instance.addObserver(this);
    _listenToSystemEvents();
    refreshNow();
  }

  void _listenToSystemEvents() {
    if (kIsWeb) return;
    // اشتراك واحد فقط طوال عمر الخدمة — لا listeners مكررة.
    _eventsSub ??= _eventsChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        // debounce: أحداث الشبكة/البطارية قد تتدفق متتالية.
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), () {
          _deviceState = _parseState(Map<dynamic, dynamic>.from(event));
          _recompute();
        });
      },
      onError: (_) {}, // فشل القناة لا يكسر النظام
    );
  }

  DeviceStateSnapshot _parseState(Map<dynamic, dynamic> res) {
    final level = res['batteryLevel'] as int? ?? -1;
    return DeviceStateSnapshot(
      batteryLevel: level >= 0 ? level : null,
      isCharging: res['isCharging'] as bool? ?? false,
      systemPowerSave: res['systemPowerSave'] as bool? ?? false,
      isMeteredNetwork: res['isMeteredNetwork'] as bool? ?? false,
      thermalStatus: res['thermalStatus'] as int? ?? -1,
      isBackground: _isBackground,
    );
  }

  /// سبب القرار الحالي (للوضع التلقائي) — يُعرض في الواجهة.
  String get autoReasonAr => PowerPolicyEngine.autoReasonAr(_deviceState);

  /// السياسة الفعلية الحالية.
  PowerPolicy get policy => _policy;

  /// الوضع الذي اختاره المستخدم.
  PowerMode get userMode => PowerPolicyEngine.parseMode(_settings.powerMode);

  /// آخر لقطة معروفة لحالة الجهاز.
  DeviceStateSnapshot get deviceState => _deviceState;

  bool get isBackground => _isBackground;

  /// تغيير وضع الطاقة من الإعدادات.
  Future<void> setUserMode(PowerMode mode) async {
    await _settings.setPowerMode(PowerPolicyEngine.modeKey(mode));
    _recompute();
  }

  /// تحديث فوري لحالة الجهاز وإعادة حساب السياسة.
  Future<void> refreshNow() async {
    _deviceState = await _readDeviceState();
    _recompute();
  }

  void _recompute() {
    final snapshot = DeviceStateSnapshot(
      batteryLevel: _deviceState.batteryLevel,
      isCharging: _deviceState.isCharging,
      systemPowerSave: _deviceState.systemPowerSave,
      isMeteredNetwork: _deviceState.isMeteredNetwork,
      thermalStatus: _deviceState.thermalStatus,
      isBackground: _isBackground,
    );
    _policy = PowerPolicyEngine.compute(userMode, snapshot);
    notifyListeners();
  }

  Future<DeviceStateSnapshot> _readDeviceState() async {
    if (kIsWeb) return const DeviceStateSnapshot();
    try {
      final res =
          await _channel.invokeMapMethod<String, dynamic>('getDeviceState');
      if (res == null) return const DeviceStateSnapshot();
      return _parseState(res);
    } catch (_) {
      // فشل الجسر الأصلي لا يكسر النظام — قيم افتراضية آمنة.
      return const DeviceStateSnapshot();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackground = _isBackground;
    _isBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
    if (_isBackground) {
      // خلفية: لا أي عمل دوري (احترام Doze/App Standby).
      _recompute();
    } else if (wasBackground) {
      // عودة للمقدمة: قراءة فورية لحالة الجهاز.
      refreshNow();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _eventsSub?.cancel();
    _eventsSub = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
