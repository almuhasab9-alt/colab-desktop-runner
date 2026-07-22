import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/constants.dart';
import '../core/power_policy.dart';
import '../services/launcher_service.dart';
import '../services/native_service.dart';
import '../services/power_service.dart';
import '../services/settings_service.dart';

/// متصفح سطح المكتب المخصص.
///
/// المزايا:
/// - HTTPS فقط (يتم التحقق قبل الوصول لهذه الشاشة).
/// - لا يتم تجاوز أخطاء SSL أبدًا (سلوك أندرويد الافتراضي: إيقاف الاتصال).
/// - إعادة اتصال بتدرج زمني: 2، 5، 10، 20 ثانية ثم التوقف.
/// - إبقاء الشاشة مضاءة (قابل للتعطيل من الإعدادات).
/// - وضع السحب الدقيق (تحويل اللمس إلى سحب بزر الفأرة الأيسر).
/// - ملاءمة الشاشة / الحجم الأصلي.
/// - شريط أدوات قابل للطي وقابل للتمرير أفقيًا.
/// - رفع الملفات عبر نافذة الملفات الرسمية.
/// - عدم إعادة تحميل الصفحة عند فتح/إغلاق لوحة المفاتيح.
class DesktopWebViewScreen extends StatefulWidget {
  final String url;
  const DesktopWebViewScreen({super.key, required this.url});

  @override
  State<DesktopWebViewScreen> createState() => _DesktopWebViewScreenState();
}

class _DesktopWebViewScreenState extends State<DesktopWebViewScreen>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  bool _loading = true;
  bool _disconnected = false;
  String? _errorDetails;
  bool _toolbarVisible = true;
  bool _dragMode = false;
  bool _fitScreen = true;

  // إعادة الاتصال بتدرج زمني
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  int _countdown = 0;

  // وضع السحب الدقيق
  Offset? _lastDragPoint;
  double _smoothX = 0, _smoothY = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = context.read<SettingsService>();
    _fitScreen = settings.fitScreen;
    _initWebView(settings);
    // إبقاء الشاشة مضاءة أثناء الجلسة — فقط إذا سمحت سياسة الطاقة
    _applyKeepScreenOnPolicy();
  }

  /// تفعيل إبقاء الشاشة مضاءة فقط إذا فعّلها المستخدم **وسمحت** سياسة
  /// الطاقة الحالية (وضع "توفير فائق" يمنعها).
  void _applyKeepScreenOnPolicy() {
    final settings = context.read<SettingsService>();
    final policy = context.read<PowerService>().policy;
    NativeService.setKeepScreenOn(
        settings.keepScreenOn && policy.allowKeepScreenOn);
  }

  void _initWebView(SettingsService settings) {
    if (kIsWeb) return; // معاينة الويب: WebView غير مدعوم
    try {
      _doInitWebView(settings);
    } catch (_) {
      // لا يجوز أن يُسقط فشل WebView التطبيق — نعرض حالة انقطاع بدل الانهيار
      _disconnected = true;
      _loading = false;
      _errorDetails = 'تعذّر تهيئة متصفح سطح المكتب على هذا الجهاز.';
    }
  }

  void _doInitWebView(SettingsService settings) {
    final controller = WebViewController()
      ..setJavaScriptMode(settings.desktopJsEnabled
          ? JavaScriptMode.unrestricted
          : JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            if (mounted) {
              setState(() {
                _loading = false;
                _disconnected = false;
                _reconnectAttempt = 0;
              });
              if (_fitScreen) await _applyFitScreen(true);
            }
          },
          onWebResourceError: (error) {
            // فقط أخطاء الإطار الرئيسي تعني انقطاع الاتصال
            if (error.isForMainFrame ?? true) {
              _onDisconnected(
                  'رمز الخطأ: ${error.errorCode}\nالنوع: ${error.errorType}');
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            // منع أي تنقل غير HTTPS
            if (uri.scheme != 'https') {
              _showMsg('تم حظر رابط غير مشفر (HTTPS فقط).');
              return NavigationDecision.prevent;
            }
            // روابط Google الرسمية تفتح بالمسار المخصص (Custom Tab)
            if (AppConstants.isGoogleLoginUrl(request.url) ||
                AppConstants.isGoogleDomain(request.url)) {
              LauncherService.openInCustomTab(request.url);
              return NavigationDecision.prevent;
            }
            // نفس نطاق سطح المكتب: اسمح
            final desktopHost = Uri.parse(widget.url).host;
            if (uri.host == desktopHost) {
              return NavigationDecision.navigate;
            }
            // نطاق مختلف: نافذة تأكيد
            _confirmExternalNavigation(request.url);
            return NavigationDecision.prevent;
          },
        ),
      );

    // إعدادات أندرويد الخاصة: رفع الملفات عبر نافذة الملفات الرسمية
    if (controller.platform is AndroidWebViewController) {
      final androidController =
          controller.platform as AndroidWebViewController;
      AndroidWebViewController.enableDebugging(false);
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setOnShowFileSelector((params) async {
        // نافذة اختيار الملفات الرسمية (SAF) — بتحكم المستخدم الكامل
        final result = await _pickFilesForUpload(params);
        return result;
      });
    }

    controller.loadRequest(Uri.parse(widget.url));
    _controller = controller;
  }

  /// رفع الملفات داخل WebView عبر نافذة الملفات الرسمية (SAF).
  /// لا يُقرأ محتوى الملف من قِبل التطبيق — يُمرَّر URI فقط إلى WebView.
  Future<List<String>> _pickFilesForUpload(FileSelectorParams params) async {
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
  }

  void _confirmExternalNavigation(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('رابط خارجي'),
          content: Text('هل تريد فتح النطاق التالي؟\n\n$host'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                LauncherService.openExternal(url);
              },
              child: const Text('فتح خارجيًا'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- انقطاع الاتصال وإعادة المحاولة ----------
  void _onDisconnected(String details) {
    if (!mounted) return;
    setState(() {
      _disconnected = true;
      _loading = false;
      _errorDetails = _sanitizeError(details);
    });
    _scheduleReconnect();
  }

  /// إخفاء أي بيانات حساسة من تفاصيل الخطأ (cookies / tokens / query)
  String _sanitizeError(String raw) {
    var s = raw;
    // إزالة query parameters من أي روابط
    s = s.replaceAllMapped(
      RegExp(r'(https?://[^\s?]+)\?[^\s]*'),
      (m) => '${m.group(1)}?[مخفي]',
    );
    s = s.replaceAll(
        RegExp(r'(cookie|token|auth)[^\s]*', caseSensitive: false),
        '[مخفي]');
    return s;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // سياسة الطاقة المركزية تحدد عدد المحاولات وطول الفواصل (مع Jitter)
    final policy = context.read<PowerService>().policy;
    final delay = PowerPolicyEngine.delayForAttempt(policy, _reconnectAttempt);
    if (delay < 0) {
      setState(() => _countdown = 0);
      return; // توقف بعد عدد محدود من المحاولات
    }
    setState(() => _countdown = delay);
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _reconnectAttempt++;
        _retry();
      }
    });
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _disconnected = false;
      _loading = true;
    });
    _controller?.loadRequest(Uri.parse(widget.url));
  }

  void _manualRetry() {
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _retry();
  }

  // ---------- ملاءمة الشاشة ----------
  Future<void> _applyFitScreen(bool fit) async {
    if (_controller == null) return;
    try {
      if (fit) {
        await _controller!.runJavaScript('''
          (function(){
            var m=document.querySelector('meta[name="viewport"]');
            if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}
            m.content='width=device-width, initial-scale=1.0, user-scalable=yes';
          })();
        ''');
      } else {
        await _controller!.runJavaScript('''
          (function(){
            var m=document.querySelector('meta[name="viewport"]');
            if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}
            m.content='width=1280, user-scalable=yes';
          })();
        ''');
      }
    } catch (_) {}
  }

  // ---------- وضع السحب الدقيق ----------
  double get _sensitivityFactor {
    switch (context.read<SettingsService>().dragSensitivity) {
      case 'slow':
        return 0.45;
      case 'direct':
        return 1.0;
      default:
        return 0.7; // متوازن
    }
  }

  /// تنعيم بسيط للإحداثيات لتخفيف الاهتزاز
  Offset _smooth(Offset p) {
    const alpha = 0.55;
    _smoothX = _smoothX + alpha * (p.dx - _smoothX);
    _smoothY = _smoothY + alpha * (p.dy - _smoothY);
    return Offset(_smoothX, _smoothY);
  }

  Future<void> _dispatchMouse(String type, Offset pos) async {
    if (_controller == null) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // تحويل من إحداثيات Flutter المنطقية إلى CSS pixels داخل الصفحة
    final x = (pos.dx).clamp(0, double.infinity).toStringAsFixed(1);
    final y = (pos.dy).clamp(0, double.infinity).toStringAsFixed(1);
    // dpr غير مستخدم مباشرة لأن الإحداثيات المنطقية تطابق CSS px غالبًا
    // ignore: unused_local_variable
    final _ = dpr;
    try {
      await _controller!.runJavaScript('''
        (function(){
          var el=document.elementFromPoint($x,$y)||document.body;
          var ev=new MouseEvent('$type',{
            bubbles:true,cancelable:true,view:window,
            clientX:$x,clientY:$y,button:0,buttons:${type == 'mouseup' ? 0 : 1}
          });
          el.dispatchEvent(ev);
          if('$type'==='mousedown'){
            var pd=new PointerEvent('pointerdown',{bubbles:true,cancelable:true,clientX:$x,clientY:$y,button:0,buttons:1,pointerType:'mouse',isPrimary:true});
            el.dispatchEvent(pd);
          } else if('$type'==='mousemove'){
            var pm=new PointerEvent('pointermove',{bubbles:true,cancelable:true,clientX:$x,clientY:$y,button:0,buttons:1,pointerType:'mouse',isPrimary:true});
            el.dispatchEvent(pm);
          } else if('$type'==='mouseup'){
            var pu=new PointerEvent('pointerup',{bubbles:true,cancelable:true,clientX:$x,clientY:$y,button:0,buttons:0,pointerType:'mouse',isPrimary:true});
            el.dispatchEvent(pu);
          }
        })();
      ''');
    } catch (_) {}
  }

  void _onDragStart(DragStartDetails d) {
    _lastDragPoint = d.localPosition;
    _smoothX = d.localPosition.dx;
    _smoothY = d.localPosition.dy;
    _dispatchMouse('mousedown', d.localPosition);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_lastDragPoint == null) return;
    // تطبيق عامل الحساسية على الإزاحة (دون تسريع مبالغ فيه)
    final delta = d.delta * _sensitivityFactor;
    final next = _lastDragPoint! + delta;
    _lastDragPoint = next;
    final smoothed = _smooth(next);
    _dispatchMouse('mousemove', smoothed);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_lastDragPoint != null) {
      _dispatchMouse('mouseup', _lastDragPoint!);
    }
    _lastDragPoint = null;
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // إيقاف المؤقتات عند انتقال التطبيق للخلفية
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _reconnectTimer?.cancel();
      NativeService.setKeepScreenOn(false);
    } else if (state == AppLifecycleState.resumed) {
      _applyKeepScreenOnPolicy();
      if (_disconnected) _scheduleReconnect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    NativeService.setKeepScreenOn(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(widget.url)?.host ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_dragMode,
        onPopInvokedWithResult: (didPop, _) {
          // زر الرجوع يخرج من وضع السحب أولًا
          if (!didPop && _dragMode) {
            setState(() => _dragMode = false);
            _showMsg('تم إيقاف وضع السحب الدقيق.');
          }
        },
        child: Scaffold(
          // مهم: تقلص WebView إلى المنطقة المرئية عند فتح لوحة المفاتيح
          resizeToAvoidBottomInset: true,
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: [
                // شريط الأدوات القابل للطي
                if (_toolbarVisible)
                  _buildToolbar(scheme, host)
                else
                  _buildCollapsedBar(scheme),
                // مؤشر وضع السحب
                if (_dragMode)
                  Container(
                    width: double.infinity,
                    color: scheme.tertiaryContainer,
                    padding: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app,
                            size: 16, color: scheme.onTertiaryContainer),
                        const SizedBox(width: 6),
                        Text(
                          'وضع السحب الدقيق مفعّل — زر الرجوع للخروج',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onTertiaryContainer),
                        ),
                      ],
                    ),
                  ),
                // منطقة WebView
                Expanded(
                  child: _buildWebArea(scheme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebArea(ColorScheme scheme) {
    if (kIsWeb) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'متصفح سطح المكتب متاح على أجهزة أندرويد.\n'
            'في معاينة الويب هذه يتم عرض الواجهة فقط.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (_disconnected) {
      return _buildDisconnected(scheme);
    }

    return Stack(
      children: [
        if (_controller != null)
          Directionality(
            textDirection: TextDirection.ltr,
            child: WebViewWidget(controller: _controller!),
          ),
        // طبقة وضع السحب الدقيق فوق WebView
        if (_dragMode)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onDragStart,
              onPanUpdate: _onDragUpdate,
              onPanEnd: _onDragEnd,
              child: const SizedBox.expand(),
            ),
          ),
        if (_loading)
          const LinearProgressIndicator(minHeight: 3),
      ],
    );
  }

  Widget _buildDisconnected(ColorScheme scheme) {
    final maxed =
        _reconnectAttempt >= AppConstants.maxAutoReconnectAttempts;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            const Text(
              'انقطع الاتصال بسطح المكتب',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              maxed
                  ? 'توقفت المحاولات التلقائية. قد يكون رابط الجلسة انتهى — '
                      'تحقق من خلية Colab أو أعد تشغيل السكربت.'
                  : _countdown > 0
                      ? 'إعادة المحاولة تلقائيًا خلال $_countdown ثانية '
                          '(محاولة ${_reconnectAttempt + 1} من ${AppConstants.maxAutoReconnectAttempts})'
                      : 'جارٍ إعادة المحاولة...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('retry_button'),
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة الآن'),
              onPressed: _manualRetry,
            ),
            if (_errorDetails != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('نسخ تفاصيل الخطأ'),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: _errorDetails!));
                  _showMsg('تم نسخ تفاصيل الخطأ (بعد إخفاء البيانات الحساسة).');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedBar(ColorScheme scheme) {
    return Material(
      color: scheme.surface,
      child: InkWell(
        onTap: () => setState(() => _toolbarVisible = true),
        child: SizedBox(
          height: 24,
          child: Center(
            child: Icon(Icons.keyboard_arrow_down,
                size: 20, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme scheme, String host) {
    return Material(
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('desktop_back_button'),
                icon: const Icon(Icons.arrow_forward),
                tooltip: 'رجوع',
                onPressed: () async {
                  if (_controller != null &&
                      await _controller!.canGoBack()) {
                    _controller!.goBack();
                  } else if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              Expanded(
                child: Text(
                  host,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: 'طي الشريط',
                onPressed: () => setState(() => _toolbarVisible = false),
              ),
            ],
          ),
          // أزرار قابلة للتمرير أفقيًا
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _toolButton(
                  key: const Key('refresh_button'),
                  icon: Icons.refresh,
                  label: 'تحديث',
                  onTap: () => _controller?.reload(),
                ),
                _toolButton(
                  key: const Key('reconnect_button'),
                  icon: Icons.sync,
                  label: 'إعادة اتصال',
                  onTap: _manualRetry,
                ),
                _toolButton(
                  key: const Key('drag_mode_button'),
                  icon: Icons.touch_app,
                  label: _dragMode ? 'إيقاف السحب' : 'السحب الدقيق',
                  active: _dragMode,
                  onTap: () {
                    setState(() => _dragMode = !_dragMode);
                    _showMsg(_dragMode
                        ? 'وضع السحب الدقيق مفعّل: إصبعك = سحب بزر الفأرة.'
                        : 'تم إيقاف وضع السحب الدقيق.');
                  },
                ),
                _toolButton(
                  icon: _fitScreen
                      ? Icons.fit_screen
                      : Icons.crop_original,
                  label: _fitScreen ? 'ملاءمة الشاشة' : 'الحجم الأصلي',
                  onTap: () async {
                    setState(() => _fitScreen = !_fitScreen);
                    await context
                        .read<SettingsService>()
                        .setFitScreen(_fitScreen);
                    await _applyFitScreen(_fitScreen);
                  },
                ),
                _toolButton(
                  icon: Icons.copy,
                  label: 'نسخ الرابط',
                  onTap: () async {
                    await Clipboard.setData(
                        ClipboardData(text: widget.url));
                    _showMsg('تم نسخ الرابط.');
                  },
                ),
                _toolButton(
                  icon: Icons.open_in_browser,
                  label: 'فتح خارجي',
                  onTap: () => LauncherService.openExternal(widget.url),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        key: key,
        avatar: Icon(icon,
            size: 18,
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor:
            active ? scheme.primary : scheme.surfaceContainerHighest,
        labelStyle: TextStyle(
            color: active ? scheme.onPrimary : scheme.onSurface),
        onPressed: onTap,
      ),
    );
  }
}


