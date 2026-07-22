// اختبارات نظام التحديث الآمن:
// - تطبيق رقعة bsdiff (BSDIFF40) وإعادة بناء الملف بايت-ببايت
// - رفض الرقع التالفة
// - منطق التحقق من المانيفست: Replay / Downgrade / انتهاء صلاحية / حزمة خاطئة
// - اختيار الرقعة الصحيحة حسب الإصدار وبصمة APK المثبّت

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter_test/flutter_test.dart';

import 'package:colab_desktop_runner/core/bspatch.dart';
import 'package:colab_desktop_runner/core/update_models.dart';

Uint8List _read(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

UpdateManifest _manifest({
  String packageName = 'com.colabdesktoprunner.runner',
  int serial = 10,
  int versionCode = 3,
  int minSupported = 1,
  String? expiresAt,
  List<Map<String, dynamic>> patches = const [],
}) {
  final json = {
    'packageName': packageName,
    'serial': serial,
    'channel': 'stable',
    if (expiresAt != null) 'expiresAt': expiresAt,
    'signingCertSha256': 'ab' * 32,
    'latest': {
      'versionName': '1.2.0',
      'versionCode': versionCode,
      'minimumSupportedVersionCode': minSupported,
      'notesAr': 'تحسينات وإصلاحات',
      'apk': {
        'url': 'https://example.com/app.apk',
        'size': 1000,
        'sha256': 'cd' * 32,
      },
    },
    'patches': patches,
  };
  return UpdateManifest.fromJsonBytes(utf8.encode(jsonEncode(json)));
}

void main() {
  group('BsPatch - تطبيق رقعة BSDIFF40 حقيقية', () {
    test('إعادة بناء الملف الجديد بايت-ببايت من الرقعة', () {
      final old = _read('old.bin');
      final patch = _read('patch.bsdiff');
      final expectedNew = _read('new.bin');
      final meta = jsonDecode(File('test/fixtures/meta.json')
          .readAsStringSync()) as Map<String, dynamic>;

      final rebuilt = BsPatch.apply(old, patch);

      expect(rebuilt.length, meta['new_len']);
      expect(rebuilt, equals(expectedNew)); // مطابقة بايت-ببايت
      // ومطابقة بصمة SHA-256 المتوقعة من CI
      final sha = c.sha256.convert(rebuilt).toString();
      expect(sha, meta['new_sha256']);
    });

    test('الرقعة أصغر بكثير من الملف الكامل (جدوى التحديث المصغّر)', () {
      final patch = _read('patch.bsdiff');
      final full = _read('new.bin');
      expect(patch.length, lessThan(full.length ~/ 10));
    });

    test('رفض رقعة بتوقيع خاطئ', () {
      final old = _read('old.bin');
      final bad = Uint8List.fromList(
          [...utf8.encode('NOTBSDIF'), ...List.filled(24, 0)]);
      expect(() => BsPatch.apply(old, bad), throwsFormatException);
    });

    test('رفض رقعة مبتورة', () {
      final old = _read('old.bin');
      final patch = _read('patch.bsdiff');
      final truncated = patch.sublist(0, patch.length ~/ 2);
      expect(() => BsPatch.apply(old, truncated),
          throwsA(anything)); // FormatException أو خطأ فك ضغط
    });

    test('رفض رقعة قصيرة جدًا', () {
      expect(() => BsPatch.apply(Uint8List(10), Uint8List(5)),
          throwsFormatException);
    });

    test('تطبيق الرقعة على ملف قديم خاطئ ينتج بصمة مختلفة (يُكشف لاحقًا)',
        () {
      final wrongOld = Uint8List.fromList(
          List.generate(_read('old.bin').length, (i) => (i * 7) & 0xFF));
      final patch = _read('patch.bsdiff');
      final meta = jsonDecode(File('test/fixtures/meta.json')
          .readAsStringSync()) as Map<String, dynamic>;
      Uint8List? rebuilt;
      try {
        rebuilt = BsPatch.apply(wrongOld, patch);
      } catch (_) {
        return; // فشل مبكر مقبول أيضًا
      }
      // إن نجح التطبيق شكليًا فبصمة SHA-256 لن تطابق — سيُرفض قبل التثبيت
      final sha = c.sha256.convert(rebuilt).toString();
      expect(sha, isNot(meta['new_sha256']));
    });
  });

  group('ManifestValidator - الحمايات الأمنية', () {
    test('تحديث متاح عند إصدار أحدث', () {
      final r = ManifestValidator.check(
        _manifest(versionCode: 3),
        installedPackageName: 'com.colabdesktoprunner.runner',
        installedVersionCode: 2,
        lastKnownSerial: 5,
      );
      expect(r, ManifestCheckResult.updateAvailable);
    });

    test('محدّث بالفعل عند نفس الإصدار (ومنع Downgrade ضمنيًا)', () {
      expect(
        ManifestValidator.check(
          _manifest(versionCode: 3),
          installedPackageName: 'com.colabdesktoprunner.runner',
          installedVersionCode: 3,
          lastKnownSerial: 5,
        ),
        ManifestCheckResult.upToDate,
      );
      // إصدار المانيفست أقدم من المثبّت → لا تحديث (منع Downgrade)
      expect(
        ManifestValidator.check(
          _manifest(versionCode: 2),
          installedPackageName: 'com.colabdesktoprunner.runner',
          installedVersionCode: 3,
          lastKnownSerial: 5,
        ),
        ManifestCheckResult.upToDate,
      );
    });

    test('رفض حزمة مختلفة (هجوم استبدال)', () {
      final r = ManifestValidator.check(
        _manifest(packageName: 'com.evil.app'),
        installedPackageName: 'com.colabdesktoprunner.runner',
        installedVersionCode: 1,
        lastKnownSerial: 0,
      );
      expect(r, ManifestCheckResult.wrongPackage);
    });

    test('رفض مانيفست منتهي الصلاحية', () {
      final r = ManifestValidator.check(
        _manifest(expiresAt: '2020-01-01T00:00:00Z'),
        installedPackageName: 'com.colabdesktoprunner.runner',
        installedVersionCode: 1,
        lastKnownSerial: 0,
        now: DateTime.utc(2026, 1, 1),
      );
      expect(r, ManifestCheckResult.expired);
    });

    test('رفض Replay: رقم تسلسلي أقدم من آخر رقم معروف', () {
      final r = ManifestValidator.check(
        _manifest(serial: 4),
        installedPackageName: 'com.colabdesktoprunner.runner',
        installedVersionCode: 1,
        lastKnownSerial: 9,
      );
      expect(r, ManifestCheckResult.replayDetected);
    });

    test('مسار الرقعة مسموح فقط ضمن النطاق المدعوم', () {
      final m = _manifest(minSupported: 2);
      expect(ManifestValidator.deltaAllowed(m, 2), true);
      expect(ManifestValidator.deltaAllowed(m, 1), false);
    });
  });

  group('UpdateManifest - اختيار الرقعة الصحيحة', () {
    test('مطابقة الإصدار وبصمة APK المثبّت معًا', () {
      final m = _manifest(patches: [
        {
          'fromVersionCode': 2,
          'fromApkSha256': 'aa' * 32,
          'toApkSha256': 'cd' * 32,
          'url': 'https://example.com/p.bin',
          'size': 100,
          'patchSha256': 'ee' * 32,
          'algorithm': 'bsdiff40',
        },
      ]);
      // مطابقة كاملة
      expect(m.patchFor(2, 'AA' * 32), isNotNull); // مقارنة غير حساسة للحالة
      // إصدار خاطئ
      expect(m.patchFor(1, 'aa' * 32), isNull);
      // بصمة خاطئة (APK معدّل أو من مصدر آخر)
      expect(m.patchFor(2, 'bb' * 32), isNull);
    });

    test('رفض رقعة لا يطابق ناتجها بصمة APK الهدف', () {
      final m = _manifest(patches: [
        {
          'fromVersionCode': 2,
          'fromApkSha256': 'aa' * 32,
          'toApkSha256': 'ff' * 32, // لا يساوي بصمة fullApk (cd*32)
          'url': 'https://example.com/p.bin',
          'size': 100,
          'patchSha256': 'ee' * 32,
          'algorithm': 'bsdiff40',
        },
      ]);
      expect(m.patchFor(2, 'aa' * 32), isNull);
    });

    test('رفض خوارزمية غير معروفة', () {
      final m = _manifest(patches: [
        {
          'fromVersionCode': 2,
          'fromApkSha256': 'aa' * 32,
          'toApkSha256': 'cd' * 32,
          'url': 'https://example.com/p.bin',
          'size': 100,
          'patchSha256': 'ee' * 32,
          'algorithm': 'xdelta3',
        },
      ]);
      expect(m.patchFor(2, 'aa' * 32), isNull);
    });
  });
}
