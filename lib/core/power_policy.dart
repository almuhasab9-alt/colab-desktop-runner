import 'dart:math';

/// أوضاع توفير الطاقة الخمسة.
enum PowerMode {
  /// تلقائي/ذكي (الافتراضي): يوازن حسب حالة البطارية والشحن ووضع توفير
  /// الطاقة في النظام.
  auto,

  /// متوازن: سلوك ثابت متوسط بغض النظر عن حالة الجهاز.
  balanced,

  /// توفير قوي: تقليل واضح للاستهلاك (فواصل أطول، بلا إبقاء شاشة).
  strong,

  /// توفير فائق: أقصى توفير ممكن دون كسر الوظائف الأساسية.
  ultra,

  /// أداء مرتفع: أفضل استجابة (مسموح فقط عند اختيار المستخدم الصريح).
  performance,
}

/// لقطة من حالة الجهاز تُغذّي القرار الذكي للوضع التلقائي.
/// جميع الحقول اختيارية الافتراضات آمنة — حتى لو فشل الجسر الأصلي
/// يبقى النظام عاملًا بسلوك متوازن.
class DeviceStateSnapshot {
  /// نسبة البطارية 0..100 (null = غير معروفة).
  final int? batteryLevel;

  /// هل الجهاز يشحن الآن؟
  final bool isCharging;

  /// هل وضع توفير الطاقة (Battery Saver) مفعّل في النظام؟
  final bool systemPowerSave;

  /// هل الشبكة الحالية محدودة البيانات (Metered / بيانات خلوية)؟
  final bool isMeteredNetwork;

  /// هل التطبيق في الخلفية؟
  final bool isBackground;

  const DeviceStateSnapshot({
    this.batteryLevel,
    this.isCharging = false,
    this.systemPowerSave = false,
    this.isMeteredNetwork = false,
    this.isBackground = false,
  });
}

/// السياسة الفعلية الناتجة — كل مستهلكي الطاقة في التطبيق يقرؤون منها
/// ولا يقررون بأنفسهم. (مصدر حقيقة واحد قابل للاختبار)
class PowerPolicy {
  /// الوضع الذي اختاره المستخدم.
  final PowerMode mode;

  /// الوضع الفعلي بعد تطبيق منطق "تلقائي/ذكي".
  final PowerMode effectiveMode;

  /// مضاعف فواصل إعادة الاتصال (1.0 = الجدول الأصلي 2/5/10/20).
  final double backoffMultiplier;

  /// أقصى عدد محاولات إعادة اتصال تلقائية.
  final int maxReconnectAttempts;

  /// هل يُسمح بإبقاء الشاشة مضاءة (حتى لو فعّلها المستخدم)؟
  final bool allowKeepScreenOn;

  /// هل تُخفَّض الرسوم المتحركة غير الضرورية؟
  final bool reduceAnimations;

  /// نسبة العشوائية (Jitter) المضافة لفواصل إعادة المحاولة لمنع التزامن.
  final double jitterRatio;

  /// هل يجب إيقاف كل المؤقتات في الخلفية فورًا؟
  final bool stopTimersInBackground;

  const PowerPolicy({
    required this.mode,
    required this.effectiveMode,
    required this.backoffMultiplier,
    required this.maxReconnectAttempts,
    required this.allowKeepScreenOn,
    required this.reduceAnimations,
    required this.jitterRatio,
    required this.stopTimersInBackground,
  });
}

/// المحرك المركزي: (وضع المستخدم + حالة الجهاز) → سياسة فعلية.
/// Dart خالص بلا أي اعتماد على Flutter — قابل للاختبار بالكامل.
class PowerPolicyEngine {
  /// جدول إعادة الاتصال الأساسي بالثواني.
  static const baseBackoffSeconds = [2, 5, 10, 20];

  static PowerMode parseMode(String? raw) {
    switch (raw) {
      case 'balanced':
        return PowerMode.balanced;
      case 'strong':
        return PowerMode.strong;
      case 'ultra':
        return PowerMode.ultra;
      case 'performance':
        return PowerMode.performance;
      default:
        return PowerMode.auto; // الافتراضي دائمًا: تلقائي/ذكي
    }
  }

  static String modeKey(PowerMode m) {
    switch (m) {
      case PowerMode.auto:
        return 'auto';
      case PowerMode.balanced:
        return 'balanced';
      case PowerMode.strong:
        return 'strong';
      case PowerMode.ultra:
        return 'ultra';
      case PowerMode.performance:
        return 'performance';
    }
  }

  static String modeLabelAr(PowerMode m) {
    switch (m) {
      case PowerMode.auto:
        return 'تلقائي (ذكي)';
      case PowerMode.balanced:
        return 'متوازن';
      case PowerMode.strong:
        return 'توفير قوي';
      case PowerMode.ultra:
        return 'توفير فائق';
      case PowerMode.performance:
        return 'أداء مرتفع';
    }
  }

  /// منطق الوضع التلقائي/الذكي:
  /// - شحن + بطارية جيدة → أداء مرتفع.
  /// - النظام في Battery Saver أو بطارية ≤ 15% → توفير فائق.
  /// - بطارية ≤ 30% أو شبكة محدودة → توفير قوي.
  /// - غير ذلك → متوازن.
  static PowerMode resolveAuto(DeviceStateSnapshot s) {
    if (s.systemPowerSave || (s.batteryLevel != null && s.batteryLevel! <= 15)) {
      return PowerMode.ultra;
    }
    if ((s.batteryLevel != null && s.batteryLevel! <= 30) ||
        s.isMeteredNetwork) {
      return PowerMode.strong;
    }
    if (s.isCharging && (s.batteryLevel == null || s.batteryLevel! >= 50)) {
      return PowerMode.performance;
    }
    return PowerMode.balanced;
  }

  /// حساب السياسة الفعلية.
  static PowerPolicy compute(PowerMode userMode, DeviceStateSnapshot state) {
    final effective =
        userMode == PowerMode.auto ? resolveAuto(state) : userMode;

    switch (effective) {
      case PowerMode.performance:
        return PowerPolicy(
          mode: userMode,
          effectiveMode: effective,
          backoffMultiplier: 1.0,
          maxReconnectAttempts: 4,
          allowKeepScreenOn: true,
          reduceAnimations: false,
          jitterRatio: 0.10,
          stopTimersInBackground: true,
        );
      case PowerMode.balanced:
        return PowerPolicy(
          mode: userMode,
          effectiveMode: effective,
          backoffMultiplier: 1.0,
          maxReconnectAttempts: 4,
          allowKeepScreenOn: true,
          reduceAnimations: false,
          jitterRatio: 0.15,
          stopTimersInBackground: true,
        );
      case PowerMode.strong:
        return PowerPolicy(
          mode: userMode,
          effectiveMode: effective,
          backoffMultiplier: 1.5,
          maxReconnectAttempts: 3,
          allowKeepScreenOn: true,
          reduceAnimations: true,
          jitterRatio: 0.20,
          stopTimersInBackground: true,
        );
      case PowerMode.ultra:
        return PowerPolicy(
          mode: userMode,
          effectiveMode: effective,
          backoffMultiplier: 2.5,
          maxReconnectAttempts: 2,
          allowKeepScreenOn: false,
          reduceAnimations: true,
          jitterRatio: 0.25,
          stopTimersInBackground: true,
        );
      case PowerMode.auto:
        // لا يصل أبدًا (auto يُحل قبل هذا) — احتياط آمن.
        return compute(PowerMode.balanced, state);
    }
  }

  /// جدول إعادة الاتصال الفعلي بالثواني (مع المضاعف، بلا Jitter).
  static List<int> backoffSchedule(PowerPolicy p) {
    return baseBackoffSeconds
        .take(p.maxReconnectAttempts)
        .map((s) => (s * p.backoffMultiplier).round())
        .toList();
  }

  /// فاصل المحاولة رقم [attempt] (0-based) بالثواني مع Jitter عشوائي
  /// لمنع التزامن (Thundering herd). [random] قابل للحقن للاختبارات.
  static int delayForAttempt(PowerPolicy p, int attempt, {Random? random}) {
    final schedule = backoffSchedule(p);
    if (attempt >= schedule.length) return -1; // توقف
    final base = schedule[attempt];
    final rnd = random ?? Random();
    // jitter موجب فقط: [0 .. jitterRatio*base]
    final jitter = (base * p.jitterRatio * rnd.nextDouble());
    return (base + jitter).round();
  }
}
