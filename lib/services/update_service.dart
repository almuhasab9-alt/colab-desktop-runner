import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/bspatch.dart';
import '../core/update_config.dart';
import '../core/update_models.dart';
import 'settings_service.dart';

/// مراحل عملية التحديث لعرضها في الواجهة.
enum UpdatePhase {
  idle,
  checking,
  updateAvailable,
  upToDate,
  downloadingPatch,
  applyingPatch,
  downloadingFullApk,
  verifying,
  readyToInstall,
  failed,
}

/// نتيجة فحص التحديث.
class UpdateCheckOutcome {
  final UpdateManifest? manifest;
  final ManifestCheckResult? result;
  final String? errorAr;
  const UpdateCheckOutcome({this.manifest, this.result, this.errorAr});
}

/// خدمة التحديث الآمن.
///
/// سلسلة التحقق الكاملة:
/// 1) تنزيل latest.json + latest.json.sig من GitHub Releases.
/// 2) التحقق من توقيع Ed25519 بالمفتاح العام المثبّت داخل التطبيق.
/// 3) التحقق من: packageName، الصلاحية الزمنية، الرقم التسلسلي (منع Replay)،
///    ومنع الرجوع لإصدار أقدم (Downgrade).
/// 4) قراءة APK المثبّت من applicationInfo.sourceDir وحساب SHA-256.
/// 5) إن وُجدت رقعة مطابقة: تنزيلها مع دعم الاستئناف (HTTP Range)،
///    التحقق من SHA-256، تطبيق bspatch، ثم التحقق من SHA-256 للناتج.
/// 6) عند الفشل بأي نقطة: التراجع لمسار APK الكامل.
/// 7) التثبيت النهائي عبر PackageInstaller (نافذة النظام) بموافقة المستخدم —
///    أندرويد نفسه يتحقق من توقيع الشهادة ورفض أي تخفيض.
class UpdateService extends ChangeNotifier {
  static const _channel =
      MethodChannel('com.almuhasab.colabdesktoprunner/native');

  final SettingsService _settings;
  UpdateService(this._settings);

  UpdatePhase _phase = UpdatePhase.idle;
  UpdatePhase get phase => _phase;

  UpdateManifest? _manifest;
  UpdateManifest? get manifest => _manifest;

  String? _errorAr;
  String? get errorAr => _errorAr;

  double _progress = 0;
  double get progress => _progress;

  int _bytesSaved = 0;

  /// البيانات الموفَّرة بمسار الرقعة مقارنة بالتنزيل الكامل.
  int get bytesSaved => _bytesSaved;

  /// هل تم التحديث فعليًا برقعة مصغّرة؟ (لا ندّعي التوفير إذا نُزّل الكامل)
  bool _usedDelta = false;
  bool get usedDelta => _usedDelta;

  /// سبب التراجع للمسار الكامل (رسالة مفهومة للمستخدم).
  String? _fallbackReasonAr;
  String? get fallbackReasonAr => _fallbackReasonAr;

  /// مدة تطبيق آخر رقعة (للقياسات).
  Duration? _lastPatchDuration;
  Duration? get lastPatchDuration => _lastPatchDuration;

  String? _readyApkPath;
  String? get readyApkPath => _readyApkPath;

  void _setPhase(UpdatePhase p, {String? error}) {
    _phase = p;
    _errorAr = error;
    notifyListeners();
  }

  // ---------------------------------------------------------------
  // 1) فحص التحديث
  // ---------------------------------------------------------------
  Future<UpdateCheckOutcome> checkForUpdate() async {
    if (kIsWeb) {
      return const UpdateCheckOutcome(
          errorAr: 'التحديثات متاحة على أندرويد فقط.');
    }
    _setPhase(UpdatePhase.checking);
    try {
      final manifestBytes = await _download(
        UpdateConfig.manifestUrl,
        maxBytes: UpdateConfig.maxManifestBytes,
      );
      final sigBytes = await _download(
        UpdateConfig.manifestSigUrl,
        maxBytes: 4096,
      );

      // التحقق من التوقيع قبل أي parsing منطقي
      final ok = await _verifyEd25519(manifestBytes, sigBytes);
      if (!ok) {
        _setPhase(UpdatePhase.failed,
            error: 'توقيع بيان التحديث غير صالح — تم الرفض.');
        return const UpdateCheckOutcome(
            errorAr: 'توقيع بيان التحديث غير صالح.');
      }

      final m = UpdateManifest.fromJsonBytes(manifestBytes);
      // تدوير المفاتيح: بيان بـ keyId مختلف يُرفض (لا مفتاح جديد من الشبكة).
      if (m.keyId != null && m.keyId != UpdateConfig.manifestKeyId) {
        _setPhase(UpdatePhase.failed,
            error: 'مفتاح توقيع البيان غير معروف — حدّث التطبيق من المصدر الرسمي.');
        return UpdateCheckOutcome(errorAr: _errorAr);
      }
      final info = await PackageInfo.fromPlatform();
      final installedCode = int.tryParse(info.buildNumber) ?? 0;

      final result = ManifestValidator.check(
        m,
        installedPackageName: info.packageName,
        installedVersionCode: installedCode,
        lastKnownSerial: _settings.lastUpdateSerial,
      );

      switch (result) {
        case ManifestCheckResult.updateAvailable:
          // حفظ الرقم التسلسلي (منع Replay مستقبلًا)
          await _settings.setLastUpdateSerial(m.serial);
          _manifest = m;
          _setPhase(UpdatePhase.updateAvailable);
          return UpdateCheckOutcome(manifest: m, result: result);
        case ManifestCheckResult.upToDate:
          await _settings.setLastUpdateSerial(m.serial);
          _setPhase(UpdatePhase.upToDate);
          return UpdateCheckOutcome(manifest: m, result: result);
        case ManifestCheckResult.wrongPackage:
          _setPhase(UpdatePhase.failed,
              error: 'بيان التحديث لحزمة مختلفة — تم الرفض.');
          return UpdateCheckOutcome(result: result, errorAr: _errorAr);
        case ManifestCheckResult.expired:
          _setPhase(UpdatePhase.failed,
              error: 'بيان التحديث منتهي الصلاحية — تم الرفض.');
          return UpdateCheckOutcome(result: result, errorAr: _errorAr);
        case ManifestCheckResult.replayDetected:
          _setPhase(UpdatePhase.failed,
              error: 'تم رصد بيان تحديث قديم (Replay) — تم الرفض.');
          return UpdateCheckOutcome(result: result, errorAr: _errorAr);
        case ManifestCheckResult.downgradeBlocked:
          _setPhase(UpdatePhase.failed,
              error: 'محاولة الرجوع لإصدار أقدم مرفوضة.');
          return UpdateCheckOutcome(result: result, errorAr: _errorAr);
      }
    } on SocketException {
      _setPhase(UpdatePhase.failed, error: 'تعذّر الاتصال بخادم التحديثات.');
      return UpdateCheckOutcome(errorAr: _errorAr);
    } catch (e) {
      _setPhase(UpdatePhase.failed, error: 'فشل فحص التحديث.');
      return UpdateCheckOutcome(errorAr: _errorAr);
    }
  }

  // ---------------------------------------------------------------
  // 2) تنفيذ التحديث (رقعة أولًا ثم APK كامل عند الفشل)
  // ---------------------------------------------------------------
  Future<bool> performUpdate({required bool wifiOnly}) async {
    final m = _manifest;
    if (m == null) return false;

    if (wifiOnly && await _isMeteredNetwork()) {
      _setPhase(UpdatePhase.failed,
          error: 'الشبكة الحالية بيانات خلوية — فعّلت التحديث عبر Wi-Fi فقط.');
      return false;
    }

    _bytesSaved = 0;
    _usedDelta = false;
    _fallbackReasonAr = null;

    // --- مسار الرقعة التفاضلية ---
    try {
      final installedPath = await _installedApkPath();
      if (installedPath == null) {
        _fallbackReasonAr = 'تعذّر الوصول لملف التطبيق المثبّت.';
      } else {
        // SHA-256 تدفقي من القرص — لا نحمّل الـ APK المثبّت في الذاكرة.
        final installedSha = await _sha256HexOfFile(installedPath);
        final info = await PackageInfo.fromPlatform();
        final installedCode = int.tryParse(info.buildNumber) ?? 0;

        if (!ManifestValidator.deltaAllowed(m, installedCode)) {
          _fallbackReasonAr = 'إصدارك الحالي أقدم من أن تدعمه الرقعة المصغّرة.';
        } else {
          final patch = m.patchFor(installedCode, installedSha);
          if (patch == null) {
            _fallbackReasonAr =
                'لا توجد رقعة مطابقة لنسختك المثبّتة (بصمة مختلفة).';
          } else if (patch.size > UpdateConfig.maxPatchBytes) {
            _fallbackReasonAr = 'حجم الرقعة يتجاوز الحد المسموح.';
          } else {
            final ok = await _applyDeltaPath(m, patch, installedPath);
            if (ok) {
              _bytesSaved = m.fullApk.size - patch.size;
              _usedDelta = true;
              return true;
            }
            _fallbackReasonAr ??=
                'فشل تطبيق/تحقق الرقعة — سيتم تنزيل التطبيق الكامل.';
          }
        }
      }
    } catch (_) {
      _fallbackReasonAr ??= 'خطأ غير متوقع في مسار الرقعة.';
    }

    // --- مسار APK الكامل (Fallback) ---
    notifyListeners();
    return _fullApkPath(m);
  }

  Future<bool> _applyDeltaPath(
      UpdateManifest m, PatchArtifact patch, String installedPath) async {
    _setPhase(UpdatePhase.downloadingPatch);
    final patchBytes = await _downloadResumable(
      patch.url,
      expectedSize: patch.size,
      maxBytes: UpdateConfig.maxPatchBytes,
      cacheName: 'patch_${patch.fromVersionCode}_to_${m.versionCode}.bin',
    );
    if (patchBytes == null) {
      _fallbackReasonAr = 'فشل تنزيل الرقعة.';
      return false;
    }

    // تحقق SHA-256 للرقعة
    if (await _sha256Hex(patchBytes) != patch.patchSha256) {
      _fallbackReasonAr = 'بصمة الرقعة غير مطابقة — تم رفضها.';
      return false;
    }

    _setPhase(UpdatePhase.applyingPatch);
    final dir = await getApplicationSupportDirectory();
    final outPath = '${dir.path}/updates/update_v${m.versionCode}.apk';
    final sw = Stopwatch()..start();
    try {
      // تطبيق الرقعة ملفًا-إلى-ملف في Isolate (ذاكرة أقل، لا تجميد)
      await compute(_applyPatchToFileIsolate, <String, dynamic>{
        'oldPath': installedPath,
        'patch': patchBytes,
        'outPath': outPath,
        'maxNewSize': UpdateConfig.maxApkBytes,
      }).timeout(UpdateConfig.patchTimeout);
    } catch (_) {
      await _deleteIfExists(outPath);
      _fallbackReasonAr = 'فشل تطبيق الرقعة على الإصدار المثبّت.';
      return false;
    }
    _lastPatchDuration = sw.elapsed;

    // التحقق النهائي: SHA-256 والحجم للـ APK المُعاد بناؤه
    _setPhase(UpdatePhase.verifying);
    final rebuiltLen = await File(outPath).length();
    if (rebuiltLen != m.fullApk.size ||
        await _sha256HexOfFile(outPath) != m.fullApk.sha256) {
      // لا يجوز بقاء APK جزئي/خاطئ قابل للتثبيت بعد الفشل.
      await _deleteIfExists(outPath);
      _fallbackReasonAr = 'الناتج بعد الترقيع غير مطابق للبصمة المتوقعة.';
      return false;
    }

    _readyApkPath = outPath;
    _setPhase(UpdatePhase.readyToInstall);
    return true;
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<bool> _fullApkPath(UpdateManifest m) async {
    _setPhase(UpdatePhase.downloadingFullApk);
    final apkBytes = await _downloadResumable(
      m.fullApk.url,
      expectedSize: m.fullApk.size,
      maxBytes: UpdateConfig.maxApkBytes,
      cacheName: 'full_v${m.versionCode}.apk.part',
    );
    if (apkBytes == null) {
      _setPhase(UpdatePhase.failed, error: 'فشل تنزيل ملف التحديث.');
      return false;
    }
    _setPhase(UpdatePhase.verifying);
    if (await _sha256Hex(apkBytes) != m.fullApk.sha256 ||
        apkBytes.length != m.fullApk.size) {
      _setPhase(UpdatePhase.failed,
          error: 'بصمة ملف التحديث غير مطابقة — تم الرفض.');
      return false;
    }
    final path = await _saveApk(apkBytes, 'update_v${m.versionCode}.apk');
    if (path == null) {
      _setPhase(UpdatePhase.failed, error: 'تعذّر حفظ ملف التحديث.');
      return false;
    }
    _readyApkPath = path;
    _setPhase(UpdatePhase.readyToInstall);
    return true;
  }

  // ---------------------------------------------------------------
  // 3) التثبيت عبر PackageInstaller (نافذة النظام + موافقة المستخدم)
  // ---------------------------------------------------------------
  Future<bool> installReadyApk() async {
    final path = _readyApkPath;
    if (path == null) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('installApk', {'path': path});
      return ok ?? false;
    } catch (_) {
      _setPhase(UpdatePhase.failed, error: 'تعذّر بدء التثبيت.');
      return false;
    }
  }

  // ---------------------------------------------------------------
  // أدوات داخلية
  // ---------------------------------------------------------------
  static Future<void> _applyPatchToFileIsolate(
      Map<String, dynamic> args) async {
    await BsPatch.applyToFile(
      oldPath: args['oldPath'] as String,
      patch: args['patch'] as Uint8List,
      outPath: args['outPath'] as String,
      maxNewSize: args['maxNewSize'] as int,
    );
  }

  Future<bool> _verifyEd25519(List<int> message, List<int> sigBytes) async {
    try {
      // التوقيع hex (128 حرفًا) أو خام (64 بايت)
      Uint8List sig;
      if (sigBytes.length >= 128) {
        final hexStr =
            String.fromCharCodes(sigBytes).trim().replaceAll('\n', '');
        sig = _hexToBytes(hexStr.substring(0, 128));
      } else if (sigBytes.length == 64) {
        sig = Uint8List.fromList(sigBytes);
      } else {
        return false;
      }
      final algo = crypto.Ed25519();
      final pubKey = crypto.SimplePublicKey(
        _hexToBytes(UpdateConfig.manifestPublicKeyHex),
        type: crypto.KeyPairType.ed25519,
      );
      return await algo.verify(
        message,
        signature: crypto.Signature(sig, publicKey: pubKey),
      );
    } catch (_) {
      return false;
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  Future<String> _sha256Hex(List<int> data) async {
    final hash = await crypto.Sha256().hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// مسار APK المثبّت الحالي من applicationInfo.sourceDir عبر القناة الأصلية.
  Future<String?> _installedApkPath() async {
    try {
      final path =
          await _channel.invokeMethod<String>('getInstalledApkPath');
      if (path == null) return null;
      if (!await File(path).exists()) return null;
      return path;
    } catch (_) {
      return null;
    }
  }

  /// SHA-256 تدفقي لملف على القرص (لا يحمّله كاملًا في الذاكرة).
  Future<String> _sha256HexOfFile(String path) async {
    final sink = crypto.Sha256().newHashSink();
    await for (final chunk in File(path).openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> _isMeteredNetwork() async {
    try {
      final res = await _channel
          .invokeMapMethod<String, dynamic>('getDeviceState');
      return res?['isMeteredNetwork'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// تنزيل بسيط بحد أقصى للحجم.
  Future<Uint8List> _download(String url, {required int maxBytes}) async {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}');
    }
    if (res.bodyBytes.length > maxBytes) {
      throw const HttpException('حجم الرد يتجاوز الحد المسموح');
    }
    return res.bodyBytes;
  }

  /// تنزيل مع دعم الاستئناف (HTTP Range) وملف مؤقت على القرص.
  Future<Uint8List?> _downloadResumable(
    String url, {
    required int expectedSize,
    required int maxBytes,
    required String cacheName,
  }) async {
    if (expectedSize > maxBytes) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final tmp = File('${dir.path}/updates/$cacheName');
      await tmp.parent.create(recursive: true);

      int have = await tmp.exists() ? await tmp.length() : 0;
      if (have > expectedSize) {
        await tmp.delete();
        have = 0;
      }

      if (have < expectedSize) {
        final req = http.Request('GET', Uri.parse(url));
        if (have > 0) req.headers['Range'] = 'bytes=$have-';
        final res =
            await req.send().timeout(const Duration(minutes: 10));
        if (res.statusCode != 200 && res.statusCode != 206) {
          return null;
        }
        // إذا تجاهل الخادم Range وأعاد 200، نبدأ من الصفر
        final sink = tmp.openWrite(
            mode: res.statusCode == 206 && have > 0
                ? FileMode.append
                : FileMode.write);
        int written = res.statusCode == 206 ? have : 0;
        await for (final chunk in res.stream) {
          written += chunk.length;
          if (written > maxBytes) {
            await sink.close();
            await tmp.delete();
            return null;
          }
          sink.add(chunk);
          _progress = expectedSize > 0 ? written / expectedSize : 0;
          notifyListeners();
        }
        await sink.close();
      }

      final bytes = await tmp.readAsBytes();
      if (bytes.length != expectedSize) {
        await tmp.delete();
        return null;
      }
      // نجاح: حذف الملف المؤقت يتم بعد التحقق في الطبقة الأعلى عند الحاجة
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveApk(Uint8List bytes, String name) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/updates/$name');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
