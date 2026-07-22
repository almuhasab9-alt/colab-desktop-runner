/// إعدادات نظام التحديث الآمن.
///
/// قناة التوزيع: مستودع عام منفصل لملفات التوزيع فقط
/// (colab-desktop-runner-releases) — روابط عامة لا تحتاج أي مصادقة،
/// بينما يبقى مستودع الكود المصدري خاصًا.
class UpdateConfig {
  UpdateConfig._();

  /// المفتاح العام Ed25519 (32 بايت hex) المثبّت داخل التطبيق.
  /// المفتاح الخاص لا يوجد إطلاقًا في المستودع — يُدار محليًا/كسر CI فقط.
  static const String manifestPublicKeyHex =
      '24f856a0ea26ed32b5b7795a5c517576928d449127249ee753a25e2fd15b2bf8';

  /// معرّف مفتاح التوقيع الحالي (لخطة تدوير المفاتيح).
  /// البيان الذي يحمل keyId مختلفًا يُرفض ما لم يكن ضمن سلسلة ثقة موقعة.
  static const String manifestKeyId = 'ed25519-2025-01';

  /// المستودع العام لملفات التوزيع (لا كود مصدر فيه).
  static const String distributionRepo =
      'almuhasab9-alt/colab-desktop-runner-releases';

  /// رابط المانيفست الموقّع (أحدث إصدار مستقر — يتجاوز pre-releases).
  static const String manifestUrl =
      'https://github.com/$distributionRepo/releases/latest/download/latest.json';

  /// رابط توقيع المانيفست (توقيع Ed25519 خام 64 بايت بترميز hex).
  static const String manifestSigUrl =
      'https://github.com/$distributionRepo/releases/latest/download/latest.json.sig';

  /// قناة التحديث الحالية لهذا البناء.
  static const String channel = 'stable';

  /// أقصى حجم مسموح لتنزيل المانيفست (حماية من الردود الضخمة).
  static const int maxManifestBytes = 256 * 1024;

  /// أقصى حجم مسموح لرقعة تفاضلية.
  static const int maxPatchBytes = 120 * 1024 * 1024;

  /// أقصى حجم مسموح لملف APK كامل.
  static const int maxApkBytes = 300 * 1024 * 1024;

  /// هامش أمان لمساحة التخزين المطلوبة قبل بدء الترقيع
  /// (حجم الناتج + هذا الهامش يجب أن يتوفر في التخزين الخاص).
  static const int minFreeSpaceMargin = 64 * 1024 * 1024;

  /// أقصى مدة مسموحة لعملية تطبيق الرقعة قبل الإجهاض.
  static const Duration patchTimeout = Duration(minutes: 5);
}
