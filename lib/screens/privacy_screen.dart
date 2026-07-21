import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import 'home_screen.dart';

/// شاشة الخصوصية لأول تشغيل — توضيح صادق لطبيعة التطبيق وحدوده
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const List<(IconData, String)> _points = [
    (
      Icons.dashboard_customize_outlined,
      'التطبيق واجهة للوصول إلى Google Colab وروابط سطح المكتب.'
    ),
    (
      Icons.verified_user_outlined,
      'تسجيل الدخول يتم عبر Google والمتصفح الرسمي (Custom Tab) — التطبيق لا يطّلع على كلمة المرور.'
    ),
    (
      Icons.cloud_outlined,
      'تشغيل الملفات يتم داخل بيئة Google Colab وليس على هاتفك.'
    ),
    (
      Icons.timer_outlined,
      'جلسات Colab قد تتوقف وفق سياسات Google.'
    ),
    (
      Icons.link_off_outlined,
      'رابط سطح المكتب مؤقت وقد يتغير عند إعادة تشغيل الجلسة.'
    ),
    (
      Icons.gpp_good_outlined,
      'التطبيق لا يتجاوز CAPTCHA أو قيود الخدمات، ولا يجمع أي تحليلات أو بيانات.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.privacy_tip_outlined,
                    size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  'الخصوصية والشفافية',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'قبل البدء، إليك ما يفعله هذا التطبيق وما لا يفعله:',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: _points.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final (icon, text) = _points[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(icon, color: scheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  text,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('privacy_accept_button'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('فهمت وأوافق'),
                  onPressed: () async {
                    final settings = context.read<SettingsService>();
                    await settings.setPrivacyAccepted(true);
                    if (context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
