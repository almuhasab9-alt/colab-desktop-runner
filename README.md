# colab-desktop-runner

سطح مكتب لينكس على Google Colab مع وكيل Qwen3.8-Max للبرمجة والبناء عبر الترمنل.

> الملف الرئيسي: `colab_desktop_v62_terminal_android_build_v32.py`

## تشغيل سريع على Colab
```python
from google.colab import drive
drive.mount('/content/drive')
%run -i "/content/colab_desktop_v62_terminal_android_build_v32.py"
```

## بناء تطبيق أندرويد (مُختبَر 100%)
السكربت `build_photo_editor.sh` يبني تطبيق «معدل الصور» من الصفر دون Android Studio:
- يختار JDK 17 (ويثبّته إن غاب)
- ينشئ مشروع Gradle كاملًا (compileSdk 34 / minSdk 24)
- يبني `app-debug.apk` ويتحقق منه عبر aapt/unzip
- ينسخه إلى `/root/Desktop/photo-editor.apk`

```bash
bash build_photo_editor.sh
# الناتج: ~/Desktop/photo-editor.apk  (5.3 MB)
```

**المتطلبات الأربعة لنجاح البناء** (مضمّنة في السكربت):
1. `JAVA_HOME` = JDK 17
2. `local.properties` بـ `sdk.dir`
3. `gradle.properties` يفعّل `android.useAndroidX=true`
4. تبعية `com.google.android.material:material:1.12.0`

## المحتويات
```
colab_desktop_v62_terminal_android_build_v32.py
build_photo_editor.sh
reports/  patches/  CHECKSUMS-SHA256.txt
```
