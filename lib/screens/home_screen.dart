import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../services/launcher_service.dart';
import '../viewmodels/app_viewmodel.dart';
import 'assistant_screen.dart';
import 'desktop_screen.dart';
import 'settings_screen.dart';
import 'colab_webview_screen.dart';

/// الشاشة الرئيسية — عربية بالكامل مع دعم RTL
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openColab(BuildContext context, String url) async {
    final vm = context.read<AppViewModel>();
    final mode = vm.settings.openColabMode;

    if (mode == 'webview') {
      // المسار الداخلي التجريبي — يحوّل تسجيل دخول Google تلقائيًا لـ Custom Tab
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ColabWebViewScreen(initialUrl: url)),
      );
    } else {
      // المسار الأساسي الآمن: Custom Tab
      final ok = await LauncherService.openInCustomTab(url);
      if (!ok && context.mounted) {
        showSnack(context, 'تعذّر فتح المتصفح. تأكد من وجود متصفح مثبت.');
      }
    }
    vm.markAssistantStep(1, true);
  }

  Future<void> _copyRunnerCode(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: AppConstants.runnerCode));
    if (context.mounted) {
      context.read<AppViewModel>().markAssistantStep(2, true);
      showSnack(context, AppConstants.copiedMessage, long: true);
    }
  }

  Future<void> _copyInstructions(BuildContext context) async {
    await Clipboard.setData(
        const ClipboardData(text: AppConstants.instructions));
    if (context.mounted) {
      showSnack(context, 'تم نسخ تعليمات التشغيل.');
    }
  }

  static void showSnack(BuildContext context, String msg,
      {bool long = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(seconds: long ? 5 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Colab Desktop Runner',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              key: const Key('settings_button'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'الإعدادات',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- بطاقة Colab ----
                _SectionCard(
                  icon: Icons.science_outlined,
                  title: 'Google Colab',
                  subtitle:
                      'يُفتح عبر المتصفح الرسمي (Custom Tab) لتسجيل دخول آمن',
                  children: [
                    FilledButton.icon(
                      key: const Key('open_colab_button'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('فتح Google Colab'),
                      onPressed: () =>
                          _openColab(context, AppConstants.colabUrl),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('new_notebook_button'),
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('فتح دفتر جديد'),
                      onPressed: () =>
                          _openColab(context, AppConstants.colabNewNotebookUrl),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- بطاقة الملف ----
                const _FileCard(),
                const SizedBox(height: 12),

                // ---- بطاقة كود التشغيل ----
                _SectionCard(
                  icon: Icons.code,
                  title: 'كود التشغيل',
                  subtitle: 'الصقه في خلية Colab ثم اضغط تشغيل',
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          AppConstants.runnerCode,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const Key('copy_code_button'),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('نسخ كود التشغيل'),
                      onPressed: () => _copyRunnerCode(context),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('copy_instructions_button'),
                      icon: const Icon(Icons.list_alt_outlined),
                      label: const Text('نسخ تعليمات التشغيل'),
                      onPressed: () => _copyInstructions(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- مساعد التشغيل ----
                _SectionCard(
                  icon: Icons.assistant_outlined,
                  title: 'مساعد التشغيل',
                  subtitle: 'تنفيذ خطوة بخطوة تحت تحكمك الكامل',
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('assistant_button'),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('بدء مساعد التشغيل'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AssistantScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- سطح المكتب ----
                _SectionCard(
                  icon: Icons.desktop_windows_outlined,
                  title: 'سطح المكتب',
                  subtitle:
                      'افتح رابط سطح المكتب الناتج من السكربت (HTTPS فقط)',
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('desktop_button'),
                      icon: const Icon(Icons.monitor),
                      label: const Text('فتح شاشة سطح المكتب'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const DesktopScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ---- تنويه ----
                Text(
                  'ملاحظة: تسجيل الدخول يتم عبر Google رسميًا. التطبيق لا يطّلع على '
                  'كلمة مرورك، ولا يتجاوز CAPTCHA أو قيود Colab.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة قسم قابلة لإعادة الاستخدام
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// بطاقة اختيار الملف وعرض "آخر ملف مختار"
class _FileCard extends StatelessWidget {
  const _FileCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AppViewModel>();
    final file = vm.pickedFile;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(Icons.insert_drive_file_outlined,
                      color: scheme.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ملف السكربت',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('py / txt / ipynb — عبر نافذة الملفات الرسمية',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (file == null)
              FilledButton.icon(
                key: const Key('pick_file_button'),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('اختيار ملف السكربت'),
                onPressed: () async {
                  final ok = await vm.pickScriptFile();
                  if (!ok && context.mounted) {
                    HomeScreen.showSnack(context, 'لم يتم اختيار أي ملف.');
                  }
                },
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.description_outlined,
                            size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            file.name,
                            key: const Key('picked_file_name'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('الحجم: ${file.sizeLabel}',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (file.modified != null)
                      Text(
                          'آخر تعديل: ${file.modified!.toString().split('.').first}',
                          style: Theme.of(context).textTheme.bodySmall),
                    Text('آخر ملف مختار — محفوظ كمرجع',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('change_file_button'),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('تغيير'),
                      onPressed: () => vm.pickScriptFile(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('share_file_button'),
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('مشاركة'),
                      onPressed: file.path == null
                          ? null
                          : () => Share.shareXFiles(
                                [XFile(file.path!)],
                                text: file.name,
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('copy_code_from_file_button'),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('نسخ كود التشغيل'),
                onPressed: () async {
                  await Clipboard.setData(
                      const ClipboardData(text: AppConstants.runnerCode));
                  if (context.mounted) {
                    vm.markAssistantStep(2, true);
                    HomeScreen.showSnack(context, AppConstants.copiedMessage,
                        long: true);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
