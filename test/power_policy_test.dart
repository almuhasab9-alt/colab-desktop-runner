import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:colab_desktop_runner/core/power_policy.dart';

void main() {
  group('PowerPolicyEngine - تحليل الأوضاع', () {
    test('الوضع الافتراضي هو تلقائي/ذكي', () {
      expect(PowerPolicyEngine.parseMode(null), PowerMode.auto);
      expect(PowerPolicyEngine.parseMode('unknown'), PowerMode.auto);
      expect(PowerPolicyEngine.parseMode('auto'), PowerMode.auto);
    });

    test('تحليل جميع الأوضاع الخمسة ذهابًا وإيابًا', () {
      for (final mode in PowerMode.values) {
        expect(
          PowerPolicyEngine.parseMode(PowerPolicyEngine.modeKey(mode)),
          mode,
        );
      }
    });

    test('لكل وضع تسمية عربية غير فارغة', () {
      for (final mode in PowerMode.values) {
        expect(PowerPolicyEngine.modeLabelAr(mode).isNotEmpty, true);
      }
    });
  });

  group('PowerPolicyEngine - المنطق الذكي (auto)', () {
    test('توفير طاقة النظام مفعّل → توفير فائق', () {
      final r = PowerPolicyEngine.resolveAuto(
          const DeviceStateSnapshot(systemPowerSave: true, batteryLevel: 80));
      expect(r, PowerMode.ultra);
    });

    test('بطارية 15% أو أقل → توفير فائق', () {
      expect(
        PowerPolicyEngine.resolveAuto(
            const DeviceStateSnapshot(batteryLevel: 15)),
        PowerMode.ultra,
      );
      expect(
        PowerPolicyEngine.resolveAuto(
            const DeviceStateSnapshot(batteryLevel: 5)),
        PowerMode.ultra,
      );
    });

    test('بطارية 30% أو أقل → توفير قوي', () {
      expect(
        PowerPolicyEngine.resolveAuto(
            const DeviceStateSnapshot(batteryLevel: 30)),
        PowerMode.strong,
      );
      expect(
        PowerPolicyEngine.resolveAuto(
            const DeviceStateSnapshot(batteryLevel: 25)),
        PowerMode.strong,
      );
    });

    test('شبكة محدودة البيانات → توفير قوي', () {
      expect(
        PowerPolicyEngine.resolveAuto(const DeviceStateSnapshot(
            batteryLevel: 90, isMeteredNetwork: true)),
        PowerMode.strong,
      );
    });

    test('شحن + بطارية جيدة → أداء مرتفع', () {
      expect(
        PowerPolicyEngine.resolveAuto(
            const DeviceStateSnapshot(batteryLevel: 80, isCharging: true)),
        PowerMode.performance,
      );
    });

    test('حالة عادية → متوازن', () {
      expect(
        PowerPolicyEngine.resolveAuto(
            const DeviceStateSnapshot(batteryLevel: 70)),
        PowerMode.balanced,
      );
      // بلا أي معلومات: متوازن (افتراض آمن)
      expect(
        PowerPolicyEngine.resolveAuto(const DeviceStateSnapshot()),
        PowerMode.balanced,
      );
    });

    test('توفير النظام يتغلب على الشحن (الأمان أولًا)', () {
      expect(
        PowerPolicyEngine.resolveAuto(const DeviceStateSnapshot(
            batteryLevel: 80, isCharging: true, systemPowerSave: true)),
        PowerMode.ultra,
      );
    });
  });

  group('PowerPolicyEngine - السياسات الفعلية', () {
    test('أداء مرتفع: جدول كامل بلا إبطاء', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.performance, const DeviceStateSnapshot());
      expect(p.effectiveMode, PowerMode.performance);
      expect(p.backoffMultiplier, 1.0);
      expect(p.maxReconnectAttempts, 4);
      expect(p.allowKeepScreenOn, true);
      expect(p.reduceAnimations, false);
      expect(PowerPolicyEngine.backoffSchedule(p), [2, 5, 10, 20]);
    });

    test('متوازن: الجدول الأصلي 2/5/10/20', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.balanced, const DeviceStateSnapshot());
      expect(PowerPolicyEngine.backoffSchedule(p), [2, 5, 10, 20]);
      expect(p.allowKeepScreenOn, true);
    });

    test('توفير قوي: فواصل أطول ومحاولات أقل', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.strong, const DeviceStateSnapshot());
      expect(p.maxReconnectAttempts, 3);
      expect(p.backoffMultiplier, 1.5);
      expect(PowerPolicyEngine.backoffSchedule(p), [3, 8, 15]);
      expect(p.reduceAnimations, true);
    });

    test('توفير فائق: يمنع إبقاء الشاشة ومحاولتان فقط', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.ultra, const DeviceStateSnapshot());
      expect(p.allowKeepScreenOn, false);
      expect(p.maxReconnectAttempts, 2);
      expect(PowerPolicyEngine.backoffSchedule(p), [5, 13]);
    });

    test('auto يُحل حسب حالة الجهاز', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.auto, const DeviceStateSnapshot(batteryLevel: 10));
      expect(p.mode, PowerMode.auto);
      expect(p.effectiveMode, PowerMode.ultra);
    });

    test('جميع الأوضاع توقف المؤقتات في الخلفية', () {
      for (final mode in PowerMode.values) {
        final p =
            PowerPolicyEngine.compute(mode, const DeviceStateSnapshot());
        expect(p.stopTimersInBackground, true,
            reason: 'الوضع $mode يجب أن يوقف المؤقتات في الخلفية');
      }
    });
  });

  group('PowerPolicyEngine - Jitter وفواصل المحاولات', () {
    test('الفاصل يحترم الحد الأدنى ويضيف Jitter موجبًا فقط', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.balanced, const DeviceStateSnapshot());
      final rnd = Random(42); // ثابت للاختبار
      for (var attempt = 0; attempt < 4; attempt++) {
        final base = PowerPolicyEngine.backoffSchedule(p)[attempt];
        final d =
            PowerPolicyEngine.delayForAttempt(p, attempt, random: rnd);
        expect(d, greaterThanOrEqualTo(base));
        expect(d, lessThanOrEqualTo((base * (1 + p.jitterRatio)).ceil()));
      }
    });

    test('تجاوز الحد الأقصى للمحاولات يرجع -1 (توقف)', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.ultra, const DeviceStateSnapshot());
      expect(PowerPolicyEngine.delayForAttempt(p, 2), -1);
      expect(PowerPolicyEngine.delayForAttempt(p, 99), -1);
    });

    test('Jitter لا يجعل التسلسل تنازليًا بشكل شاذ (تصاعدي عمومًا)', () {
      final p = PowerPolicyEngine.compute(
          PowerMode.strong, const DeviceStateSnapshot());
      final rnd = Random(7);
      final delays = [
        for (var i = 0; i < p.maxReconnectAttempts; i++)
          PowerPolicyEngine.delayForAttempt(p, i, random: rnd)
      ];
      for (var i = 1; i < delays.length; i++) {
        expect(delays[i], greaterThan(delays[i - 1]));
      }
    });
  });
}
