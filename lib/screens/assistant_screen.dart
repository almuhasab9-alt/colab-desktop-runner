import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../services/launcher_service.dart';
import '../viewmodels/app_viewmodel.dart';
import 'desktop_screen.dart';

/// وصف خطوة في مساعد التشغيل
class _AssistantStep {
  final String title;
  final String description;
  final IconData icon;
  final String? actionLabel;

  const _AssistantStep({
    required this.title,
    required this.description,
    required this.icon,
    this.actionLabel,
  });
}

/// مساعد التشغيل — خطوة بخطوة تحت تحكم المستخدم الكامل.
/// لا يوجد أي نقر تلقائي أو رفع خفي أو AccessibilityService.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  int _current = 0;

  static const List<_AssistantStep> _steps = [
    _AssistantStep(
      title: 'اختيار ملف السكربت',
      description:
          'اختر ملف Python من هاتفك عبر نافذة الملفات الرسمية. يدعم التطبيق ملفات py و txt و ipynb.',
      icon: Icons.folder_open_outlined,
      actionLabel: 'اختيار الملف',
    ),
    _AssistantStep(
      title: 'فتح Google Colab',
      description:
          'سيُفتح Colab في المتصفح الرسمي (Custom Tab). سجّل الدخول بحساب Google إذا طُلب منك — التطبيق لا يطّلع على كلمة مرورك.',
      icon: Icons.open_in_new,
      actionLabel: 'فتح Colab',
    ),
    _AssistantStep(
      title: 'نسخ كود التشغيل',
      description:
          'انسخ كود التشغيل الجاهز إلى حافظة الهاتف بضغطة واحدة.',
      icon: Icons.copy_all_outlined,
      actionLabel: 'نسخ الكود',
    ),
    _AssistantStep(
      title: 'لصق الكود في خلية',
      description:
          'ارجع إلى Colab، أنشئ خلية جديدة (+ Code)، ثم اضغط مطولًا داخل الخلية واختر "لصق".',
      icon: Icons.content_paste_outlined,
    ),
    _AssistantStep(
      title: 'تشغيل الخلية',
      description:
          'اضغط زر التشغيل (▶) بجانب الخلية بنفسك. قد يطلب Colab الاتصال بوقت تشغيل — وافق عليه.',
      icon: Icons.play_circle_outline,
    ),
    _AssistantStep(
      title: 'اختيار الملف عند نافذة الرفع',
      description:
          'عند ظهور زر "Choose Files" في مخرجات الخلية، اضغطه واختر ملف السكربت من نافذة الملفات الرسمية.',
      icon: Icons.upload_file_outlined,
    ),
    _AssistantStep(
      title: 'انتظار رابط سطح المكتب',
      description:
          'انتظر حتى يطبع السكربت رابط سطح المكتب (مثل رابط trycloudflare.com). انسخه من مخرجات الخلية.',
      icon: Icons.hourglass_bottom_outlined,
    ),
    _AssistantStep(
      title: 'فتح رابط سطح المكتب',
      description:
          'الصق الرابط في شاشة سطح المكتب داخل التطبيق للتحكم الكامل مع لوحة المفاتيح ووضع السحب الدقيق.',
      icon: Icons.desktop_windows_outlined,
      actionLabel: 'فتح شاشة سطح المكتب',
    ),
  ];

  Future<void> _executeAction(BuildContext context, int index) async {
    final vm = context.read<AppViewModel>();
    switch (index) {
      case 0:
        final ok = await vm.pickScriptFile();
        if (ok) _markDone(index);
        break;
      case 1:
        await LauncherService.openInCustomTab(AppConstants.colabUrl);
        _markDone(index);
        break;
      case 2:
        await Clipboard.setData(
            const ClipboardData(text: AppConstants.runnerCode));
        _markDone(index);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppConstants.copiedMessage)),
          );
        }
        break;
      case 7:
        _markDone(index);
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DesktopScreen()),
          );
        }
        break;
    }
  }

  void _markDone(int index) {
    context.read<AppViewModel>().markAssistantStep(index, true);
    if (index == _current && _current < _steps.length - 1) {
      setState(() => _current++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AppViewModel>();
    final done = vm.assistantDone;
    final scheme = Theme.of(context).colorScheme;
    final step = _steps[_current];
    final isDone = done[_current];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مساعد التشغيل'),
          actions: [
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'إعادة ضبط التقدم',
              onPressed: () {
                vm.resetAssistant();
                setState(() => _current = 0);
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // مؤشر التقدم
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: done.where((d) => d).length / _steps.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الخطوة ${_current + 1} من ${_steps.length} — '
                      'أُنجز ${done.where((d) => d).length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // شريط الخطوات
              SizedBox(
                height: 56,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _steps.length,
                  itemBuilder: (context, i) {
                    final active = i == _current;
                    final finished = done[i];
                    return GestureDetector(
                      onTap: () => setState(() => _current = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: active
                              ? scheme.primaryContainer
                              : finished
                                  ? scheme.secondaryContainer
                                  : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              finished
                                  ? Icons.check_circle
                                  : _steps[i].icon,
                              size: 18,
                              color: active
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text('${i + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: active
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurfaceVariant,
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // بطاقة الخطوة الحالية
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: isDone
                                ? scheme.secondaryContainer
                                : scheme.primaryContainer,
                            child: Icon(
                              isDone ? Icons.check_circle : step.icon,
                              size: 32,
                              color: isDone
                                  ? scheme.onSecondaryContainer
                                  : scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            step.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            step.description,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(height: 1.6),
                          ),
                          const SizedBox(height: 20),
                          if (step.actionLabel != null)
                            FilledButton.icon(
                              key: Key('assistant_action_$_current'),
                              icon: Icon(step.icon),
                              label: Text(step.actionLabel!),
                              onPressed: () =>
                                  _executeAction(context, _current),
                            ),
                          const SizedBox(height: 12),
                          // علامة إنجاز يحددها المستخدم
                          CheckboxListTile(
                            key: Key('assistant_check_$_current'),
                            value: isDone,
                            onChanged: (v) => vm.markAssistantStep(
                                _current, v ?? false),
                            title: const Text('تمّت هذه الخطوة'),
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            tileColor: scheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // أزرار التنقل
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('assistant_prev'),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('السابق'),
                        onPressed: _current > 0
                            ? () => setState(() => _current--)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('assistant_next'),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(_current < _steps.length - 1
                            ? 'التالي'
                            : 'إنهاء'),
                        onPressed: () {
                          if (_current < _steps.length - 1) {
                            setState(() => _current++);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
