import 'dart:convert';

/// وصف ملف APK كامل داخل المانيفست.
class ApkArtifact {
  final String url;
  final int size;
  final String sha256;

  const ApkArtifact({
    required this.url,
    required this.size,
    required this.sha256,
  });

  factory ApkArtifact.fromJson(Map<String, dynamic> j) => ApkArtifact(
        url: j['url'] as String,
        size: j['size'] as int,
        sha256: (j['sha256'] as String).toLowerCase(),
      );
}

/// وصف رقعة تفاضلية (bsdiff) من إصدار محدد إلى الإصدار الأخير.
class PatchArtifact {
  final int fromVersionCode;
  final String fromApkSha256;
  final String toApkSha256;
  final String url;
  final int size;
  final String patchSha256;
  final String algorithm; // bsdiff40

  const PatchArtifact({
    required this.fromVersionCode,
    required this.fromApkSha256,
    required this.toApkSha256,
    required this.url,
    required this.size,
    required this.patchSha256,
    required this.algorithm,
  });

  factory PatchArtifact.fromJson(Map<String, dynamic> j) => PatchArtifact(
        fromVersionCode: j['fromVersionCode'] as int,
        fromApkSha256: (j['fromApkSha256'] as String).toLowerCase(),
        toApkSha256: (j['toApkSha256'] as String).toLowerCase(),
        url: j['url'] as String,
        size: j['size'] as int,
        patchSha256: (j['patchSha256'] as String).toLowerCase(),
        algorithm: j['algorithm'] as String,
      );
}

/// مانيفست التحديث الموقّع (المحتوى الداخلي بعد التحقق من التوقيع).
class UpdateManifest {
  final String packageName;
  final int serial; // رقم تسلسلي متزايد — منع إعادة التشغيل (Replay)
  final String channel; // stable | beta | canary
  final DateTime? expiresAt;
  final String versionName;
  final int versionCode;
  final int minimumSupportedVersionCode;
  final String signingCertSha256; // بصمة شهادة توقيع APK المتوقعة
  final ApkArtifact fullApk;
  final List<PatchArtifact> patches;
  final String notesAr;

  const UpdateManifest({
    required this.packageName,
    required this.serial,
    required this.channel,
    required this.expiresAt,
    required this.versionName,
    required this.versionCode,
    required this.minimumSupportedVersionCode,
    required this.signingCertSha256,
    required this.fullApk,
    required this.patches,
    required this.notesAr,
  });

  factory UpdateManifest.fromJsonBytes(List<int> bytes) {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final latest = j['latest'] as Map<String, dynamic>;
    return UpdateManifest(
      packageName: j['packageName'] as String,
      serial: j['serial'] as int,
      channel: j['channel'] as String? ?? 'stable',
      expiresAt: j['expiresAt'] != null
          ? DateTime.tryParse(j['expiresAt'] as String)
          : null,
      versionName: latest['versionName'] as String,
      versionCode: latest['versionCode'] as int,
      minimumSupportedVersionCode:
          latest['minimumSupportedVersionCode'] as int? ?? 1,
      signingCertSha256:
          (j['signingCertSha256'] as String).toLowerCase().replaceAll(':', ''),
      fullApk:
          ApkArtifact.fromJson(latest['apk'] as Map<String, dynamic>),
      patches: [
        for (final p in (j['patches'] as List? ?? []))
          PatchArtifact.fromJson(p as Map<String, dynamic>)
      ],
      notesAr: latest['notesAr'] as String? ?? '',
    );
  }

  /// البحث عن رقعة مطابقة للإصدار المثبّت وبصمة APK المثبّت.
  PatchArtifact? patchFor(int installedVersionCode, String installedApkSha256) {
    final sha = installedApkSha256.toLowerCase();
    for (final p in patches) {
      if (p.fromVersionCode == installedVersionCode &&
          p.fromApkSha256 == sha &&
          p.algorithm == 'bsdiff40' &&
          p.toApkSha256 == fullApk.sha256) {
        return p;
      }
    }
    return null;
  }
}

/// نتيجة فحص صلاحية المانيفست ضد حالة الجهاز.
enum ManifestCheckResult {
  /// يوجد تحديث صالح.
  updateAvailable,

  /// التطبيق محدّث بالفعل.
  upToDate,

  /// مرفوض: حزمة مختلفة (هجوم استبدال).
  wrongPackage,

  /// مرفوض: المانيفست منتهي الصلاحية.
  expired,

  /// مرفوض: رقم تسلسلي أقدم من آخر رقم معروف (هجوم Replay).
  replayDetected,

  /// مرفوض: الإصدار المعروض أقدم أو مساوٍ (منع Downgrade).
  downgradeBlocked,
}

/// منطق التحقق الأمني للمانيفست — Dart خالص قابل للاختبار بالكامل.
class ManifestValidator {
  /// [now] و [lastKnownSerial] قابلان للحقن للاختبارات.
  static ManifestCheckResult check(
    UpdateManifest m, {
    required String installedPackageName,
    required int installedVersionCode,
    required int lastKnownSerial,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now().toUtc();
    if (m.packageName != installedPackageName) {
      return ManifestCheckResult.wrongPackage;
    }
    if (m.expiresAt != null && t.isAfter(m.expiresAt!)) {
      return ManifestCheckResult.expired;
    }
    if (m.serial < lastKnownSerial) {
      return ManifestCheckResult.replayDetected;
    }
    if (m.versionCode <= installedVersionCode) {
      return ManifestCheckResult.upToDate;
    }
    // منع أي عرض لإصدار أدنى من الحد الأدنى المدعوم لا معنى له هنا
    // (versionCode > installed يكفي لمنع Downgrade).
    return ManifestCheckResult.updateAvailable;
  }

  /// هل يُسمح بمسار الرقعة التفاضلية؟ (الإصدار المثبّت ضمن النطاق المدعوم)
  static bool deltaAllowed(UpdateManifest m, int installedVersionCode) {
    return installedVersionCode >= m.minimumSupportedVersionCode;
  }
}
