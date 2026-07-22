import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/update_config.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';

/// شاشة التحديثات — فحص وتنزيل وتثبيت التحديثات الموقّعة من GitHub Releases.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  String _installedVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() =>
            _installedVersion = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      if (mounted) setState(() => _installedVersion = 'غير معروف');
    }
  }

  String _savedDataLabel(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} كيلوبايت';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميغابايت';
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateService>();
    final settings = context.read<SettingsService>();
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التحديثات')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // الإصدار الحالي والقناة
              Card(
                child: ListTile(
                  leading: Icon(Icons.verified_outlined, color: scheme.primary),
                  title: Text('الإصدار المثبّت: $_installedVersion'),
                  subtitle: const Text(
                      'قناة التحديث: ${UpdateConfig.channel} — '
                      'التحديثات موقّعة رقميًا (Ed25519) ويتم التحقق منها قبل التثبيت'),
                ),
              ),
              const SizedBox(height: 12),

              // خيار Wi-Fi فقط
              Card(
                child: SwitchListTile(
                  key: const Key('update_wifi_only_switch'),
                  value: settings.updateWifiOnly,
                  onChanged: (v) async {
                    await settings.setUpdateWifiOnly(v);
                    if (mounted) setState(() {});
                  },
                  title: const Text('التنزيل عبر Wi-Fi فقط'),
                  subtitle: const Text('لتجنّب استهلاك البيانات الخلوية'),
                ),
              ),
              const SizedBox(height: 12),

              // الحالة الحالية
              _buildStatusCard(updates, scheme),
              const SizedBox(height: 16),

              // أزرار التحكم
              _buildActions(updates, settings),

              const SizedBox(height: 20),
              // توضيح أمني
              Card(
                color: scheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, color: scheme.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text('كيف نحمي تحديثاتك؟',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• بيان التحديث موقّع رقميًا ويُرفض أي بيان غير موقّع أو منتهي الصلاحية.\n'
                        '• تُحمَّل رقعة تفاضلية صغيرة عند الإمكان بدلًا من التطبيق كاملًا (توفير بيانات).\n'
                        '• تُحسب بصمة SHA-256 للملف الناتج وتُقارن قبل التثبيت.\n'
                        '• الرجوع لإصدار أقدم مرفوض دائمًا، والتثبيت يتم عبر نافذة النظام الرسمية بموافقتك.\n'
                        '• عند فشل الرقعة يجري تنزيل التطبيق كاملًا تلقائيًا.',
                        style: TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(UpdateService updates, ColorScheme scheme) {
    final (icon, color, title, subtitle) = switch (updates.phase) {
      UpdatePhase.idle => (
          Icons.system_update_alt,
          scheme.onSurfaceVariant,
          'اضغط "فحص التحديثات" للبدء',
          null,
        ),
      UpdatePhase.checking => (
          Icons.sync,
          scheme.primary,
          'جارٍ فحص التحديثات...',
          null,
        ),
      UpdatePhase.upToDate => (
          Icons.check_circle,
          Colors.green,
          'تطبيقك محدّث بالفعل',
          null,
        ),
      UpdatePhase.updateAvailable => (
          Icons.new_releases,
          scheme.primary,
          'يتوفر تحديث جديد: ${updates.manifest?.versionName ?? ''}',
          updates.manifest?.notesAr.isNotEmpty == true
              ? updates.manifest!.notesAr
              : null,
        ),
      UpdatePhase.downloadingPatch => (
          Icons.download,
          scheme.primary,
          'جارٍ تنزيل التحديث المصغّر (رقعة تفاضلية)...',
          '${(updates.progress * 100).toStringAsFixed(0)}%',
        ),
      UpdatePhase.applyingPatch => (
          Icons.build_circle_outlined,
          scheme.primary,
          'جارٍ تطبيق الرقعة وإعادة بناء التحديث...',
          null,
        ),
      UpdatePhase.downloadingFullApk => (
          Icons.download,
          scheme.primary,
          'جارٍ تنزيل التحديث الكامل...',
          '${(updates.progress * 100).toStringAsFixed(0)}%',
        ),
      UpdatePhase.verifying => (
          Icons.fact_check_outlined,
          scheme.primary,
          'جارٍ التحقق من سلامة التحديث (SHA-256)...',
          null,
        ),
      UpdatePhase.readyToInstall => (
          Icons.install_mobile,
          Colors.green,
          'التحديث جاهز للتثبيت',
          updates.bytesSaved > 0
              ? 'وفّرت ${_savedDataLabel(updates.bytesSaved)} من البيانات بفضل التحديث المصغّر'
              : null,
        ),
      UpdatePhase.failed => (
          Icons.error_outline,
          scheme.error,
          updates.errorAr ?? 'فشل التحديث',
          null,
        ),
    };

    final busy = updates.phase == UpdatePhase.checking ||
        updates.phase == UpdatePhase.downloadingPatch ||
        updates.phase == UpdatePhase.downloadingFullApk ||
        updates.phase == UpdatePhase.applyingPatch ||
        updates.phase == UpdatePhase.verifying;

    return Card(
      key: const Key('update_status_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (updates.phase == UpdatePhase.downloadingPatch ||
                            updates.phase ==
                                UpdatePhase.downloadingFullApk) &&
                        updates.progress > 0
                    ? updates.progress
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions(UpdateService updates, SettingsService settings) {
    switch (updates.phase) {
      case UpdatePhase.idle:
      case UpdatePhase.upToDate:
      case UpdatePhase.failed:
        return FilledButton.icon(
          key: const Key('check_updates_button'),
          icon: const Icon(Icons.refresh),
          label: const Text('فحص التحديثات'),
          onPressed: () => updates.checkForUpdate(),
        );
      case UpdatePhase.updateAvailable:
        return Column(
          children: [
            FilledButton.icon(
              key: const Key('download_update_button'),
              icon: const Icon(Icons.download),
              label: const Text('تنزيل التحديث'),
              onPressed: () =>
                  updates.performUpdate(wifiOnly: settings.updateWifiOnly),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => updates.checkForUpdate(),
              child: const Text('إعادة الفحص'),
            ),
          ],
        );
      case UpdatePhase.readyToInstall:
        return FilledButton.icon(
          key: const Key('install_update_button'),
          icon: const Icon(Icons.install_mobile),
          label: const Text('تثبيت التحديث الآن'),
          onPressed: () => updates.installReadyApk(),
        );
      default:
        return const SizedBox.shrink(); // أثناء التنزيل/التطبيق
    }
  }
}
