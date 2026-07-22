/// إعدادات نظام التحديث الآمن.
///
/// قناة التوزيع: GitHub Releases.
/// ملاحظة صادقة: ما دام المستودع خاصًا (Private) فلن تكون أصول الإصدارات
/// متاحة بدون مصادقة — يجب جعل المستودع عامًا أو نقل الأصول لاستضافة عامة
/// قبل تفعيل التحديثات للمستخدمين النهائيين.
class UpdateConfig {
  UpdateConfig._();

  /// المفتاح العام Ed25519 (32 بايت hex) المثبّت داخل التطبيق.
  /// المفتاح الخاص لا يوجد إطلاقًا في المستودع — يُدار محليًا/كسر CI فقط.
  static const String manifestPublicKeyHex =
      '24f856a0ea26ed32b5b7795a5c517576928d449127249ee753a25e2fd15b2bf8';

  /// رابط المانيفست الموقّع (أحدث إصدار دائمًا).
  static const String manifestUrl =
      'https://github.com/almuhasab9-alt/colab-desktop-runner/releases/latest/download/latest.json';

  /// رابط توقيع المانيفست (توقيع Ed25519 خام 64 بايت بترميز hex).
  static const String manifestSigUrl =
      'https://github.com/almuhasab9-alt/colab-desktop-runner/releases/latest/download/latest.json.sig';

  /// قناة التحديث الحالية لهذا البناء.
  static const String channel = 'stable';

  /// أقصى حجم مسموح لتنزيل المانيفست (حماية من الردود الضخمة).
  static const int maxManifestBytes = 256 * 1024;

  /// أقصى حجم مسموح لرقعة تفاضلية.
  static const int maxPatchBytes = 120 * 1024 * 1024;

  /// أقصى حجم مسموح لملف APK كامل.
  static const int maxApkBytes = 300 * 1024 * 1024;
}
