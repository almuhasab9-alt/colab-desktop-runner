// اختبارات Colab Desktop Runner
// تغطي: التحقق من HTTPS، رفض HTTP، كود التشغيل، الإعدادات،
// الشاشة الرئيسية، شاشة الخصوصية، مساعد التشغيل، شاشة سطح المكتب،
// عدم تسريب البيانات الحساسة، تدرج إعادة الاتصال.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:colab_desktop_runner/core/constants.dart';
import 'package:colab_desktop_runner/core/url_validator.dart';
import 'package:colab_desktop_runner/services/settings_service.dart';
import 'package:colab_desktop_runner/viewmodels/app_viewmodel.dart';
import 'package:colab_desktop_runner/screens/home_screen.dart';
import 'package:colab_desktop_runner/screens/privacy_screen.dart';
import 'package:colab_desktop_runner/screens/desktop_screen.dart';
import 'package:colab_desktop_runner/screens/assistant_screen.dart';

Future<SettingsService> _makeSettings() async {
  SharedPreferences.setMockInitialValues({});
  return SettingsService.create();
}

Widget _wrap(Widget child, SettingsService settings) {
  return MultiProvider(
    providers: [
      Provider<SettingsService>.value(value: settings),
      ChangeNotifierProvider(create: (_) => AppViewModel(settings)),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('التحقق من روابط سطح المكتب (UrlValidator)', () {
    test('يقبل روابط HTTPS الصحيحة', () {
      final r = UrlValidator.check('https://abc.trycloudflare.com');
      expect(r.valid, true);
      expect(r.host, 'abc.trycloudflare.com');
    });

    test('يرفض HTTP غير المشفر', () {
      final r = UrlValidator.check('http://abc.trycloudflare.com');
      expect(r.valid, false);
      expect(r.error, contains('HTTPS'));
    });

    test('يرفض الروابط الفارغة وغير الصالحة', () {
      expect(UrlValidator.check('').valid, false);
      expect(UrlValidator.check('   ').valid, false);
      expect(UrlValidator.check('ftp://x.com').valid, false);
    });

    test('يضيف https تلقائيًا عند كتابة النطاق فقط', () {
      final r = UrlValidator.check('abc.trycloudflare.com');
      expect(r.valid, true);
      expect(r.uri!.scheme, 'https');
    });
  });

  group('كود التشغيل والثوابت', () {
    test('كود التشغيل يحتوي على العناصر الأساسية', () {
      expect(AppConstants.runnerCode, contains('files.upload()'));
      expect(AppConstants.runnerCode, contains('from google.colab import files'));
      expect(AppConstants.runnerCode, contains('run_line_magic'));
    });

    test('كشف صفحات تسجيل دخول Google', () {
      expect(
          AppConstants.isGoogleLoginUrl(
              'https://accounts.google.com/signin'),
          true);
      expect(
          AppConstants.isGoogleLoginUrl(
              'https://example.com/?error=disallowed_useragent'),
          true);
      expect(
          AppConstants.isGoogleLoginUrl('https://abc.trycloudflare.com'),
          false);
    });

    test('تدرج إعادة الاتصال: 2، 5، 10، 20 ثانية ثم توقف', () {
      expect(AppConstants.reconnectBackoffSeconds, [2, 5, 10, 20]);
      expect(AppConstants.maxAutoReconnectAttempts, 4);
    });
  });

  group('خدمة الإعدادات (SettingsService)', () {
    test('القيم الافتراضية آمنة: Custom Tab افتراضي', () async {
      final s = await _makeSettings();
      expect(s.openColabMode, 'custom_tab');
      expect(s.keepScreenOn, true);
      expect(s.privacyAccepted, false);
    });

    test('الاحتفاظ بمرجع الملف بعد إعادة إنشاء الخدمة', () async {
      SharedPreferences.setMockInitialValues({});
      var s = await SettingsService.create();
      await s.saveLastFile(name: 'سكربت تجريبي.py', size: 2048);
      // إعادة إنشاء (محاكاة إعادة تشغيل التطبيق)
      s = await SettingsService.create();
      expect(s.lastFileName, 'سكربت تجريبي.py');
      expect(s.lastFileSize, 2048);
    });

    test('دعم أسماء الملفات العربية والمسافات', () async {
      final s = await _makeSettings();
      await s.saveLastFile(name: 'ملف التشغيل الرئيسي v2.py', size: 100);
      expect(s.lastFileName, 'ملف التشغيل الرئيسي v2.py');
    });

    test('النطاقات الموثوقة وسجل الروابط', () async {
      final s = await _makeSettings();
      await s.addTrustedDomain('abc.trycloudflare.com');
      expect(s.trustedDomains, contains('abc.trycloudflare.com'));
      await s.addUrlToHistory('https://abc.trycloudflare.com');
      expect(s.urlHistory.length, 1);
      await s.clearUrlHistory();
      expect(s.urlHistory, isEmpty);
    });

    test('لا تُخزَّن أي بيانات حساسة (لا tokens ولا cookies)', () async {
      final s = await _makeSettings();
      await s.saveLastFile(name: 'test.py', size: 1);
      await s.addUrlToHistory('https://x.trycloudflare.com');
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect(key.toLowerCase(), isNot(contains('token')));
        expect(key.toLowerCase(), isNot(contains('cookie')));
        expect(key.toLowerCase(), isNot(contains('password')));
      }
    });
  });

  group('ViewModel - مساعد التشغيل', () {
    test('تحديد وإلغاء خطوات المساعد وحفظ التقدم', () async {
      final s = await _makeSettings();
      final vm = AppViewModel(s);
      vm.markAssistantStep(0, true);
      vm.markAssistantStep(2, true);
      expect(vm.assistantDone[0], true);
      expect(vm.assistantDone[1], false);
      expect(vm.assistantDone[2], true);
      // استعادة التقدم في viewmodel جديد
      final vm2 = AppViewModel(s);
      expect(vm2.assistantDone[0], true);
      expect(vm2.assistantDone[2], true);
      vm2.resetAssistant();
      expect(vm2.assistantDone.every((d) => !d), true);
    });
  });

  group('شاشة الخصوصية', () {
    testWidgets('تعرض النقاط وزر الموافقة', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const PrivacyScreen(), s));
      expect(find.text('فهمت وأوافق'), findsOneWidget);
      expect(find.text('الخصوصية والشفافية'), findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const Key('privacy_accept_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_accept_button')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(s.privacyAccepted, true);
    });
  });

  group('الشاشة الرئيسية', () {
    testWidgets('تعرض جميع الأزرار الأساسية', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const HomeScreen(), s));
      expect(find.byKey(const Key('open_colab_button')), findsOneWidget);
      expect(find.byKey(const Key('new_notebook_button')), findsOneWidget);
      expect(find.byKey(const Key('pick_file_button')), findsOneWidget);
      expect(find.text('فتح Google Colab'), findsOneWidget);
      expect(find.text('فتح دفتر جديد'), findsOneWidget);
      expect(find.text('اختيار ملف السكربت'), findsOneWidget);
      // زر نسخ الكود
      await tester.scrollUntilVisible(
          find.byKey(const Key('copy_code_button')), 200);
      expect(find.byKey(const Key('copy_code_button')), findsOneWidget);
    });

    testWidgets('نسخ كود التشغيل يعرض رسالة التأكيد', (tester) async {
      // Mock قناة الحافظة والتحقق من أن الكود الصحيح يُنسخ فعلًا
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const HomeScreen(), s));
      await tester.scrollUntilVisible(
          find.byKey(const Key('copy_code_button')), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('copy_code_button')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // التحقق من أن كود التشغيل الصحيح نُسخ إلى الحافظة
      expect(copiedText, AppConstants.runnerCode);
    });

    testWidgets('الاتجاه RTL مفعّل', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const HomeScreen(), s));
      final directionality = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byType(Scaffold).first,
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(directionality.textDirection, TextDirection.rtl);
    });
  });

  group('شاشة سطح المكتب', () {
    testWidgets('رفض رابط HTTP وعرض رسالة الخطأ', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const DesktopScreen(), s));
      await tester.enterText(find.byKey(const Key('desktop_url_field')),
          'http://abc.trycloudflare.com');
      await tester.tap(find.byKey(const Key('open_desktop_url_button')));
      await tester.pump();
      expect(find.textContaining('HTTPS'), findsWidgets);
    });

    testWidgets('رابط HTTPS يعرض نافذة تأكيد النطاق', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const DesktopScreen(), s));
      await tester.enterText(find.byKey(const Key('desktop_url_field')),
          'https://abc.trycloudflare.com');
      await tester.tap(find.byKey(const Key('open_desktop_url_button')));
      await tester.pumpAndSettle();
      expect(find.text('تأكيد فتح النطاق'), findsOneWidget);
      expect(find.text('abc.trycloudflare.com'), findsOneWidget);
      // إلغاء
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(s.trustedDomains, isEmpty);
    });

    testWidgets('الموافقة على النطاق تضيفه للموثوقين', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const DesktopScreen(), s));
      await tester.enterText(find.byKey(const Key('desktop_url_field')),
          'https://xyz.trycloudflare.com');
      await tester.tap(find.byKey(const Key('open_desktop_url_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve_domain_button')));
      // لا نستخدم pumpAndSettle لأن شاشة WebView تحتوي مؤقتات
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.trustedDomains, contains('xyz.trycloudflare.com'));
      expect(s.urlHistory, contains('https://xyz.trycloudflare.com'));
      // تنظيف: إغلاق شاشة WebView لإيقاف المؤقتات
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pop();
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('مساعد التشغيل', () {
    testWidgets('يعرض الخطوات ويتنقل بينها', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const AssistantScreen(), s));
      expect(find.text('اختيار ملف السكربت'), findsOneWidget);
      expect(find.textContaining('الخطوة 1 من 8'), findsOneWidget);
      // التالي
      await tester.tap(find.byKey(const Key('assistant_next')));
      await tester.pumpAndSettle();
      expect(find.text('فتح Google Colab'), findsOneWidget);
      // السابق
      await tester.tap(find.byKey(const Key('assistant_prev')));
      await tester.pumpAndSettle();
      expect(find.text('اختيار ملف السكربت'), findsOneWidget);
    });

    testWidgets('علامة الإنجاز يحددها المستخدم', (tester) async {
      final s = await _makeSettings();
      await tester.pumpWidget(_wrap(const AssistantScreen(), s));
      await tester.tap(find.byKey(const Key('assistant_check_0')));
      await tester.pump();
      final vm = AppViewModel(s);
      expect(vm.assistantDone[0], true);
    });
  });
}
