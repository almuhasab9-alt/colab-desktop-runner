# Colab Desktop Runner - ProGuard/R8 rules

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep MainActivity (MethodChannel)
-keep class com.almuhasab.colabdesktoprunner.MainActivity { *; }

# WebView
-keepclassmembers class * extends android.webkit.WebChromeClient {
    public void openFileChooser(...);
}

# لا تسجل أي معلومات حساسة - إزالة استدعاءات Log في الإصدار النهائي
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# Flutter deferred components (Play Core) - غير مستخدمة في هذا التطبيق
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
