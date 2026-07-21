import 'package:shared_preferences/shared_preferences.dart';

/// خدمة تخزين الإعدادات غير الحساسة.
/// لا يتم تخزين أي كلمات مرور أو Tokens أو Cookies هنا.
class SettingsService {
  static const _kThemeMode = 'theme_mode'; // system | light | dark
  static const _kKeepScreenOn = 'keep_screen_on';
  static const _kOpenColabMode = 'open_colab_mode'; // custom_tab | webview
  static const _kDragSensitivity = 'drag_sensitivity'; // slow|balanced|direct
  static const _kDesktopJsEnabled = 'desktop_js_enabled';
  static const _kPrivacyAccepted = 'privacy_accepted';
  static const _kLastFileName = 'last_file_name';
  static const _kLastFileSize = 'last_file_size';
  static const _kLastFileModified = 'last_file_modified';
  static const _kLastFilePath = 'last_file_path';
  static const _kTrustedDomains = 'trusted_domains';
  static const _kUrlHistory = 'url_history';
  static const _kFitScreen = 'fit_screen';
  static const _kAssistantProgress = 'assistant_progress';
  static const _kPowerMode = 'power_mode'; // auto|balanced|strong|ultra|performance

  final SharedPreferences _prefs;
  SettingsService(this._prefs);

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  // ---- السمة ----
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString(_kThemeMode, v);

  // ---- إبقاء الشاشة مضاءة ----
  bool get keepScreenOn => _prefs.getBool(_kKeepScreenOn) ?? true;
  Future<void> setKeepScreenOn(bool v) => _prefs.setBool(_kKeepScreenOn, v);

  // ---- طريقة فتح Colab ----
  String get openColabMode => _prefs.getString(_kOpenColabMode) ?? 'custom_tab';
  Future<void> setOpenColabMode(String v) =>
      _prefs.setString(_kOpenColabMode, v);

  // ---- حساسية السحب ----
  String get dragSensitivity =>
      _prefs.getString(_kDragSensitivity) ?? 'balanced';
  Future<void> setDragSensitivity(String v) =>
      _prefs.setString(_kDragSensitivity, v);

  // ---- JavaScript لمتصفح سطح المكتب ----
  bool get desktopJsEnabled => _prefs.getBool(_kDesktopJsEnabled) ?? true;
  Future<void> setDesktopJsEnabled(bool v) =>
      _prefs.setBool(_kDesktopJsEnabled, v);

  // ---- ملاءمة الشاشة ----
  bool get fitScreen => _prefs.getBool(_kFitScreen) ?? true;
  Future<void> setFitScreen(bool v) => _prefs.setBool(_kFitScreen, v);

  // ---- شاشة الخصوصية ----
  bool get privacyAccepted => _prefs.getBool(_kPrivacyAccepted) ?? false;
  Future<void> setPrivacyAccepted(bool v) =>
      _prefs.setBool(_kPrivacyAccepted, v);

  // ---- آخر ملف مختار (مرجع فقط، لا يُنسخ المحتوى) ----
  String? get lastFileName => _prefs.getString(_kLastFileName);
  int? get lastFileSize => _prefs.getInt(_kLastFileSize);
  String? get lastFileModified => _prefs.getString(_kLastFileModified);
  String? get lastFilePath => _prefs.getString(_kLastFilePath);

  Future<void> saveLastFile({
    required String name,
    required int size,
    String? modified,
    String? path,
  }) async {
    await _prefs.setString(_kLastFileName, name);
    await _prefs.setInt(_kLastFileSize, size);
    if (modified != null) {
      await _prefs.setString(_kLastFileModified, modified);
    }
    if (path != null) {
      await _prefs.setString(_kLastFilePath, path);
    }
  }

  Future<void> clearLastFile() async {
    await _prefs.remove(_kLastFileName);
    await _prefs.remove(_kLastFileSize);
    await _prefs.remove(_kLastFileModified);
    await _prefs.remove(_kLastFilePath);
  }

  // ---- النطاقات الموثوقة (بموافقة المستخدم) ----
  List<String> get trustedDomains =>
      _prefs.getStringList(_kTrustedDomains) ?? [];
  Future<void> addTrustedDomain(String domain) async {
    final list = trustedDomains;
    if (!list.contains(domain)) {
      list.add(domain);
      await _prefs.setStringList(_kTrustedDomains, list);
    }
  }

  Future<void> clearTrustedDomains() => _prefs.remove(_kTrustedDomains);

  // ---- سجل الروابط ----
  List<String> get urlHistory => _prefs.getStringList(_kUrlHistory) ?? [];
  Future<void> addUrlToHistory(String url) async {
    final list = urlHistory;
    list.remove(url);
    list.insert(0, url);
    if (list.length > 10) list.removeRange(10, list.length);
    await _prefs.setStringList(_kUrlHistory, list);
  }

  Future<void> clearUrlHistory() => _prefs.remove(_kUrlHistory);

  // ---- تقدم مساعد التشغيل ----
  List<String> get assistantProgress =>
      _prefs.getStringList(_kAssistantProgress) ?? [];
  Future<void> setAssistantProgress(List<String> done) =>
      _prefs.setStringList(_kAssistantProgress, done);

  // ---- وضع توفير الطاقة ----
  /// الافتراضي: 'auto' (تلقائي/ذكي)
  String get powerMode => _prefs.getString(_kPowerMode) ?? 'auto';
  Future<void> setPowerMode(String v) => _prefs.setString(_kPowerMode, v);

  // ---- إعادة ضبط التطبيق ----
  Future<void> resetAll() => _prefs.clear();
}
