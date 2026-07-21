import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';
import '../viewmodels/app_viewmodel.dart';
import 'privacy_screen.dart';

/// شاشة الإعدادات
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _clearWebViewData() async {
    if (kIsWeb) {
      _snack('غير متاح في معاينة الويب.');
      return;
    }
    try {
      final cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();
      _snack('تم مسح بيانات متصفح سطح المكتب (Cookies).');
    } catch (_) {
      _snack('تعذّر مسح البيانات.');
    }
  }

  Future<void> _resetApp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعادة ضبط التطبيق'),
          content: const Text(
              'سيتم مسح جميع الإعدادات والسجلات المحفوظة. هل أنت متأكد؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('إعادة ضبط'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      final settings = context.read<SettingsService>();
      await settings.resetAll();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PrivacyScreen()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsService>();
    final vm = context.watch<AppViewModel>();
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- طريقة فتح Colab ----
              _sectionHeader(context, 'فتح Google Colab'),
              Card(
                child: Column(
                  children: [
                    RadioListTile<String>(
                      key: const Key('mode_custom_tab'),
                      value: 'custom_tab',
                      groupValue: settings.openColabMode,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setOpenColabMode(v!)),
                      title: const Text('المتصفح الرسمي (Custom Tab)'),
                      subtitle: const Text(
                          'الافتراضي والموصى به — تسجيل دخول Google آمن ورسمي'),
                    ),
                    RadioListTile<String>(
                      key: const Key('mode_webview'),
                      value: 'webview',
                      groupValue: settings.openColabMode,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setOpenColabMode(v!)),
                      title: const Text('WebView داخلي (تجريبي)'),
                      subtitle: const Text(
                          'تسجيل دخول Google سيُحوَّل تلقائيًا للمتصفح الرسمي'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ---- المظهر ----
              _sectionHeader(context, 'المظهر'),
              Card(
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'system',
                      groupValue: settings.themeMode,
                      onChanged: (v) => vm.setThemeMode(v!),
                      title: const Text('تلقائي (حسب النظام)'),
                    ),
                    RadioListTile<String>(
                      value: 'light',
                      groupValue: settings.themeMode,
                      onChanged: (v) => vm.setThemeMode(v!),
                      title: const Text('فاتح'),
                    ),
                    RadioListTile<String>(
                      value: 'dark',
                      groupValue: settings.themeMode,
                      onChanged: (v) => vm.setThemeMode(v!),
                      title: const Text('داكن'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ---- سطح المكتب ----
              _sectionHeader(context, 'متصفح سطح المكتب'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const Key('keep_screen_on_switch'),
                      value: settings.keepScreenOn,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setKeepScreenOn(v)),
                      title: const Text('إبقاء الشاشة مضاءة'),
                      subtitle:
                          const Text('أثناء جلسة سطح المكتب فقط'),
                    ),
                    SwitchListTile(
                      key: const Key('js_switch'),
                      value: settings.desktopJsEnabled,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setDesktopJsEnabled(v)),
                      title: const Text('تفعيل JavaScript'),
                      subtitle: const Text(
                          'لمتصفح سطح المكتب فقط — مطلوب لمعظم واجهات سطح المكتب'),
                    ),
                    SwitchListTile(
                      value: settings.fitScreen,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setFitScreen(v)),
                      title: const Text('ملاءمة الشاشة افتراضيًا'),
                      subtitle: const Text(
                          'عند التعطيل يُعرض بالحجم الأصلي (1280px)'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ---- حساسية السحب ----
              _sectionHeader(context, 'وضع السحب الدقيق'),
              Card(
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'slow',
                      groupValue: settings.dragSensitivity,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setDragSensitivity(v!)),
                      title: const Text('بطيء ودقيق'),
                      subtitle: const Text('للتحكم الدقيق في العناصر الصغيرة'),
                    ),
                    RadioListTile<String>(
                      value: 'balanced',
                      groupValue: settings.dragSensitivity,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setDragSensitivity(v!)),
                      title: const Text('متوازن'),
                      subtitle: const Text('الافتراضي'),
                    ),
                    RadioListTile<String>(
                      value: 'direct',
                      groupValue: settings.dragSensitivity,
                      onChanged: (v) => vm.updateSetting(
                          () => settings.setDragSensitivity(v!)),
                      title: const Text('مباشر'),
                      subtitle: const Text('حركة مطابقة لإصبعك 1:1'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ---- البيانات ----
              _sectionHeader(context, 'البيانات'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('مسح بيانات متصفح سطح المكتب'),
                      subtitle: const Text('Cookies وبيانات WebView'),
                      onTap: _clearWebViewData,
                    ),
                    ListTile(
                      leading: const Icon(Icons.history_toggle_off),
                      title: const Text('مسح سجل الروابط'),
                      onTap: () async {
                        await settings.clearUrlHistory();
                        await settings.clearTrustedDomains();
                        _snack('تم مسح سجل الروابط والنطاقات الموثوقة.');
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.restart_alt,
                          color: scheme.error),
                      title: Text('إعادة ضبط التطبيق',
                          style: TextStyle(color: scheme.error)),
                      onTap: _resetApp,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ---- توضيح جلسة Google ----
              Card(
                color: scheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: scheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'إدارة جلسة حساب Google (تسجيل الخروج، مسح البيانات) '
                          'تتم من المتصفح الافتراضي أو من إعدادات حساب Google — '
                          'وليس من هذا التطبيق، لأن تسجيل الدخول يتم في المتصفح الرسمي.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Colab Desktop Runner — الإصدار 1.0.0\n'
                  'بدون تحليلات • بدون إعلانات • بدون جمع بيانات',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
