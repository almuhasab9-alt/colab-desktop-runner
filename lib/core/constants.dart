/// ثوابت التطبيق - Colab Desktop Runner
library;

class AppConstants {
  AppConstants._();

  static const String appName = 'Colab Desktop Runner';

  /// روابط Google Colab الرسمية
  static const String colabUrl = 'https://colab.research.google.com/';
  static const String colabNewNotebookUrl =
      'https://colab.research.google.com/#create=true';

  /// كود التشغيل الجاهز الذي يُنسخ إلى حافظة الهاتف
  /// ليلصقه المستخدم بنفسه في خلية Colab ويشغّلها بنفسه.
  static const String runnerCode = r'''from google.colab import files
from pathlib import Path

uploaded = files.upload()
if not uploaded:
    raise RuntimeError("لم يتم اختيار أي ملف.")

filename = next(iter(uploaded))
path = Path("/content") / filename
print(f"تشغيل الملف: {path.name}")
get_ipython().run_line_magic("run", f'-i "{path}"')''';

  /// تعليمات التشغيل المختصرة
  static const String instructions = '''خطوات التشغيل:
1. افتح Colab.
2. أنشئ خلية جديدة.
3. الصق كود التشغيل.
4. اضغط تشغيل.
5. اختر ملف Python عند ظهور نافذة الرفع.
6. اقبل أذونات Google Drive إذا طلبها السكربت.''';

  /// رسالة ما بعد نسخ الكود
  static const String copiedMessage =
      'تم نسخ كود التشغيل. افتح Colab، أنشئ خلية، الصق الكود ثم اضغط تشغيل.';

  /// امتدادات الملفات المسموح باختيارها
  static const List<String> allowedExtensions = ['py', 'txt', 'ipynb'];

  /// تدرج زمني لإعادة الاتصال (بالثواني)
  static const List<int> reconnectBackoffSeconds = [2, 5, 10, 20];

  /// أقصى عدد لمحاولات إعادة الاتصال التلقائية
  static const int maxAutoReconnectAttempts = 4;

  /// نطاقات Google الرسمية (تُفتح عبر المسار المخصص / Custom Tab)
  static const List<String> googleDomains = [
    'colab.research.google.com',
    'accounts.google.com',
    'google.com',
    'www.google.com',
    'drive.google.com',
    'myaccount.google.com',
  ];

  /// كشف صفحات تسجيل دخول Google (تُفتح دائمًا في Custom Tab)
  static bool isGoogleLoginUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == 'accounts.google.com' ||
        (uri.host.endsWith('.google.com') && uri.path.contains('signin')) ||
        url.contains('disallowed_useragent');
  }

  /// هل الرابط ضمن نطاقات Google الرسمية؟
  static bool isGoogleDomain(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return googleDomains.any(
      (d) => uri.host == d || uri.host.endsWith('.$d'),
    );
  }
}
