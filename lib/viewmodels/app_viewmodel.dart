import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/constants.dart';
import '../services/settings_service.dart';
import '../services/native_service.dart';

/// معلومات الملف المختار (مرجع فقط — لا يُقرأ المحتوى إلا عند الحاجة)
class PickedScriptFile {
  final String name;
  final int size;
  final String? path;
  final DateTime? modified;

  PickedScriptFile({
    required this.name,
    required this.size,
    this.path,
    this.modified,
  });

  String get sizeLabel {
    if (size < 1024) return '$size بايت';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} كيلوبايت';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} ميغابايت';
  }
}

/// ViewModel رئيسي وفق معمارية MVVM
class AppViewModel extends ChangeNotifier {
  final SettingsService settings;

  AppViewModel(this.settings) {
    _loadSavedFile();
    _loadAssistantProgress();
  }

  // ---------- السمة ----------
  ThemeMode get themeMode {
    switch (settings.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(String mode) async {
    await settings.setThemeMode(mode);
    notifyListeners();
  }

  // ---------- الملف المختار ----------
  PickedScriptFile? _pickedFile;
  PickedScriptFile? get pickedFile => _pickedFile;

  void _loadSavedFile() {
    final name = settings.lastFileName;
    if (name != null) {
      _pickedFile = PickedScriptFile(
        name: name,
        size: settings.lastFileSize ?? 0,
        path: settings.lastFilePath,
        modified: settings.lastFileModified != null
            ? DateTime.tryParse(settings.lastFileModified!)
            : null,
      );
    }
  }

  /// اختيار ملف عبر Storage Access Framework (ACTION_OPEN_DOCUMENT)
  /// file_picker يستخدم SAF على أندرويد مع persistable permission تلقائيًا.
  Future<bool> pickScriptFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppConstants.allowedExtensions,
        withData: false, // لا نقرأ المحتوى — مرجع فقط
      );
      if (result == null || result.files.isEmpty) return false;

      final f = result.files.first;
      DateTime? modified;
      if (!kIsWeb && f.path != null) {
        // آخر تعديل إن توفر (دون قراءة المحتوى)
        try {
          // ignore: avoid_slow_async_io
          modified = null; // يُترك فارغًا إن لم يتوفر عبر SAF
        } catch (_) {}
      }

      _pickedFile = PickedScriptFile(
        name: f.name,
        size: f.size,
        path: kIsWeb ? null : f.path,
        modified: modified,
      );

      await settings.saveLastFile(
        name: f.name,
        size: f.size,
        modified: modified?.toIso8601String(),
        path: kIsWeb ? null : f.path,
      );

      // تحديث تقدم المساعد
      markAssistantStep(0, true);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearPickedFile() async {
    _pickedFile = null;
    await settings.clearLastFile();
    notifyListeners();
  }

  // ---------- مساعد التشغيل ----------
  static const int assistantStepsCount = 8;
  List<bool> _assistantDone = List.filled(assistantStepsCount, false);
  List<bool> get assistantDone => List.unmodifiable(_assistantDone);

  void _loadAssistantProgress() {
    final saved = settings.assistantProgress;
    for (int i = 0; i < assistantStepsCount; i++) {
      _assistantDone[i] = saved.contains('$i');
    }
  }

  void markAssistantStep(int index, bool done) {
    if (index < 0 || index >= assistantStepsCount) return;
    _assistantDone[index] = done;
    final list = <String>[];
    for (int i = 0; i < assistantStepsCount; i++) {
      if (_assistantDone[i]) list.add('$i');
    }
    settings.setAssistantProgress(list);
    notifyListeners();
  }

  void resetAssistant() {
    _assistantDone = List.filled(assistantStepsCount, false);
    settings.setAssistantProgress([]);
    notifyListeners();
  }

  // ---------- إبقاء الشاشة مضاءة ----------
  Future<void> applyKeepScreenOn(bool active) async {
    if (settings.keepScreenOn && active) {
      await NativeService.setKeepScreenOn(true);
    } else {
      await NativeService.setKeepScreenOn(false);
    }
  }

  // ---------- إعدادات عامة ----------
  Future<void> updateSetting(Future<void> Function() update) async {
    await update();
    notifyListeners();
  }
}
