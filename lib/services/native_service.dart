import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// قناة التواصل مع طبقة Kotlin الأصلية (MainActivity.kt)
/// تُستخدم فقط لتفعيل/تعطيل إبقاء الشاشة مضاءة (FLAG_KEEP_SCREEN_ON).
class NativeService {
  static const _channel =
      MethodChannel('com.almuhasab.colabdesktoprunner/native');

  /// تفعيل أو تعطيل إبقاء الشاشة مضاءة أثناء جلسة سطح المكتب
  static Future<void> setKeepScreenOn(bool enabled) async {
    if (kIsWeb) return; // غير مدعوم في معاينة الويب
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'enabled': enabled});
    } on PlatformException {
      // لا تُسقط التطبيق إذا فشلت القناة الأصلية
    } on MissingPluginException {
      // بيئة اختبار أو ويب
    }
  }
}
