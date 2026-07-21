import 'package:url_launcher/url_launcher.dart';

/// خدمة فتح الروابط الخارجية.
///
/// المسار الأساسي الآمن: Android Custom Tabs (عبر LaunchMode.inAppBrowserView)
/// لفتح Google Colab وتسجيل الدخول الرسمي دون اعتراض أي بيانات،
/// ودون حقن JavaScript، ودون تخزين كلمة مرور Google.
///
/// ملاحظة صادقة: جلسة Google تُدار من المتصفح الافتراضي/Custom Tab،
/// ولا تنتقل Cookies تلقائيًا إلى WebView الداخلي.
class LauncherService {
  /// فتح رابط في Custom Tab (المسار الموصى به لـ Colab وGoogle)
  static Future<bool> openInCustomTab(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') return false;
    return launchUrl(
      uri,
      mode: LaunchMode.inAppBrowserView, // Custom Tabs على أندرويد
    );
  }

  /// فتح رابط في المتصفح الخارجي الافتراضي
  static Future<bool> openExternal(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
