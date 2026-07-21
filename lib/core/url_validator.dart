/// أداة التحقق من روابط سطح المكتب.
/// - HTTPS فقط، لا يُفتح HTTP غير المشفر تلقائيًا أبدًا.
/// - عرض اسم النطاق قبل الفتح ليوافق عليه المستخدم.
class UrlValidator {
  UrlValidator._();

  /// نتيجة التحقق من الرابط
  static UrlCheckResult check(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return UrlCheckResult(valid: false, error: 'الرجاء إدخال رابط.');
    }

    Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      // جرّب إضافة https:// إن كتب المستخدم النطاق فقط
      uri = Uri.tryParse('https://$trimmed');
      if (uri == null || uri.host.isEmpty) {
        return UrlCheckResult(valid: false, error: 'الرابط غير صالح.');
      }
    }

    if (uri.scheme == 'http') {
      return UrlCheckResult(
        valid: false,
        error: 'هذا الرابط غير مشفر (HTTP). لأمانك، يُسمح فقط بروابط HTTPS.',
        host: uri.host,
      );
    }

    if (uri.scheme != 'https') {
      return UrlCheckResult(
        valid: false,
        error: 'يُسمح فقط بروابط HTTPS.',
        host: uri.host,
      );
    }

    return UrlCheckResult(valid: true, uri: uri, host: uri.host);
  }
}

class UrlCheckResult {
  final bool valid;
  final Uri? uri;
  final String? host;
  final String? error;

  UrlCheckResult({required this.valid, this.uri, this.host, this.error});
}
