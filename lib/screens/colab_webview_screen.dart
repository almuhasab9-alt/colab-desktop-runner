import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/constants.dart';
import '../services/launcher_service.dart';

/// المسار الداخلي الاختياري (تجريبي) لفتح Colab داخل WebView.
///
/// سياسة صارمة وصادقة:
/// - عند اكتشاف صفحة تسجيل دخول Google أو خطأ disallowed_useragent،
///   تُفتح الصفحة تلقائيًا في Custom Tab (المتصفح الرسمي).
/// - لا يُستخدم User-Agent مزيف لتجاوز سياسات Google.
/// - لا يُدّعى أن جلسة Custom Tab تنتقل إلى WebView — لا تنتقل.
/// - Custom Tab هو المسار الافتراضي الموصى به من الإعدادات.
class ColabWebViewScreen extends StatefulWidget {
  final String initialUrl;
  const ColabWebViewScreen({super.key, required this.initialUrl});

  @override
  State<ColabWebViewScreen> createState() => _ColabWebViewScreenState();
}

class _ColabWebViewScreenState extends State<ColabWebViewScreen> {
  WebViewController? _controller;
  bool _loading = true;
  bool _loginRedirected = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _init();
  }

  void _init() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _loading = true);
            _checkLoginRedirect(url);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || uri.scheme != 'https') {
              return NavigationDecision.prevent;
            }
            // صفحات تسجيل دخول Google → Custom Tab فورًا (بدون حيل)
            if (AppConstants.isGoogleLoginUrl(request.url)) {
              _redirectToCustomTab(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // دعم رفع الملفات داخل WebView (نافذة الملفات الرسمية / SAF)
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setOnShowFileSelector((params) async {
        try {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: params.mode == FileSelectorMode.openMultiple,
            withData: false,
          );
          if (result == null || result.files.isEmpty) return [];
          return result.files
              .where((f) => f.path != null)
              .map((f) => Uri.file(f.path!).toString())
              .toList();
        } catch (_) {
          return [];
        }
      });
    }

    controller.loadRequest(Uri.parse(widget.initialUrl));
    _controller = controller;
  }

  void _checkLoginRedirect(String url) {
    if (_loginRedirected) return;
    if (AppConstants.isGoogleLoginUrl(url)) {
      _redirectToCustomTab(url);
    }
  }

  Future<void> _redirectToCustomTab(String url) async {
    _loginRedirected = true;
    await LauncherService.openInCustomTab(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 6),
          content: Text(
            'تسجيل دخول Google لا يعمل داخل WebView وفق سياسات Google. '
            'فُتحت الصفحة في المتصفح الرسمي — أكمل تسجيل الدخول هناك ثم '
            'استخدم Colab من المتصفح الرسمي.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Colab (تجريبي)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () => _controller?.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'فتح في المتصفح الرسمي',
              onPressed: () =>
                  LauncherService.openInCustomTab(widget.initialUrl),
            ),
          ],
        ),
        body: SafeArea(
          child: kIsWeb
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'هذه الشاشة تعمل على أجهزة أندرويد.\n'
                      'في معاينة الويب يتم عرض الواجهة فقط.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    // تنويه صادق حول WebView
                    Container(
                      width: double.infinity,
                      color: Theme.of(context)
                          .colorScheme
                          .tertiaryContainer
                          .withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Text(
                        'وضع تجريبي: تسجيل دخول Google سيُحوَّل تلقائيًا '
                        'إلى المتصفح الرسمي.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_loading)
                      const LinearProgressIndicator(minHeight: 3),
                    Expanded(
                      child: _controller == null
                          ? const SizedBox.shrink()
                          : Directionality(
                              textDirection: TextDirection.ltr,
                              child:
                                  WebViewWidget(controller: _controller!),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
