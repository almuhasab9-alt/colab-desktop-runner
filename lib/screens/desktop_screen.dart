import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/url_validator.dart';
import '../services/settings_service.dart';
import 'desktop_webview_screen.dart';

/// شاشة "سطح المكتب" — إدخال رابط سطح المكتب والتحقق منه قبل الفتح.
/// - HTTPS فقط.
/// - عرض اسم النطاق وطلب موافقة المستخدم قبل الفتح.
/// - سجل الروابط الأخيرة.
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _controller.text = data!.text!.trim();
        _error = null;
      });
    }
  }

  Future<void> _openUrl(String input) async {
    final result = UrlValidator.check(input);
    if (!result.valid) {
      setState(() => _error = result.error);
      return;
    }
    setState(() => _error = null);

    final settings = context.read<SettingsService>();
    final host = result.host!;
    final trusted = settings.trustedDomains.contains(host);

    // عرض اسم النطاق وطلب الموافقة إن لم يكن موثوقًا مسبقًا
    if (!trusted) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تأكيد فتح النطاق'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('أنت على وشك فتح رابط سطح المكتب على النطاق:'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    host,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'افتح فقط الروابط الصادرة من السكربت الخاص بك. '
                  'الرابط مؤقت وقد يتغير عند إعادة تشغيل الجلسة.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const Key('approve_domain_button'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('موافق، افتح'),
              ),
            ],
          ),
        ),
      );
      if (approved != true) return;
      await settings.addTrustedDomain(host);
    }

    await settings.addUrlToHistory(result.uri.toString());
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DesktopWebViewScreen(url: result.uri!.toString()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsService>();
    final history = settings.urlHistory;
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سطح المكتب')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.link, color: scheme.primary),
                            const SizedBox(width: 8),
                            Text('رابط سطح المكتب',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'الصق الرابط الناتج من السكربت (مثل رابط trycloudflare.com). '
                          'يُسمح فقط بروابط HTTPS المشفرة.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextField(
                            key: const Key('desktop_url_field'),
                            controller: _controller,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: InputDecoration(
                              hintText: 'https://example.trycloudflare.com',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              errorText: _error,
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.paste),
                                tooltip: 'لصق',
                                onPressed: _pasteFromClipboard,
                              ),
                            ),
                            onSubmitted: _openUrl,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('open_desktop_url_button'),
                          icon: const Icon(Icons.desktop_windows_outlined),
                          label: const Text('فتح سطح المكتب'),
                          onPressed: () => _openUrl(_controller.text),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (history.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('الروابط الأخيرة',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('مسح السجل'),
                        onPressed: () async {
                          await settings.clearUrlHistory();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  ...history.map(
                    (url) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(
                          url,
                          textDirection: TextDirection.ltr,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'نسخ الرابط',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: url));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('تم نسخ الرابط.')),
                              );
                            }
                          },
                        ),
                        onTap: () {
                          _controller.text = url;
                          _openUrl(url);
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Card(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: scheme.tertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'رابط سطح المكتب مؤقت ويتغير عند إعادة تشغيل جلسة Colab. '
                            'لن يُفتح أي رابط HTTP غير مشفر.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
