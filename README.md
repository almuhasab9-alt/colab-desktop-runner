# colab-desktop-runner

مشروع تشغيل سطح مكتب لينكس على Google Colab مع وصول MCP، وحفظ الحالة في Drive، ووكيل Qwen3.8-Max للبرمجة والبناء عبر الترمنل.

> الملف الحالي: `colab_desktop_v62_terminal_android_build_v32.py`

## الإصدار الحالي V32 / v62

- جسر Qwen3.8-Max v3 (إرسال بزر Send، اكتشاف CDP ديناميكي، استخراج نظيف للجواب).
- الوكيل **يبني تطبيقات أندرويد عبر الترمنل وGradle/SDK فقط** — أُزيل ارتباط بناء APK بواجهة Android Studio.
- تحقق إلزامي من الـAPK (aapt/unzip) ونسخه إلى سطح المكتب.
- يُرفق سكربت جاهز: `build_photo_editor.sh` (تطبيق «معدل الصور»).

## الاستخدام في Colab

```python
from google.colab import drive
drive.mount('/content/drive')
path = "/content/colab_desktop_v62_terminal_android_build_v32.py"
%run -i "{path}"
```

## بناء تطبيق معدل الصور (اختبار)

بعد الإقلاع، في ترمنل نظيف:
```bash
bash build_photo_editor.sh
```
سيُنشئ المشروع في `/root/agent-workspaces/qwen/photo-editor` وينسخ APK إلى `/root/Desktop/photo-editor.apk`.

## المحتويات

```text
colab_desktop_v62_terminal_android_build_v32.py
build_photo_editor.sh
reports/
patches/
CHECKSUMS-SHA256.txt
```

## ملاحظة أمان

لا تضع توكنات أو مفاتيح في ملفات الكود. غيّر/ألغِ أي توكن عُرض في المحادثة.
