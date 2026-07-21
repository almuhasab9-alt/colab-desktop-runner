# Colab Desktop Runner

**اسم الحزمة:** `com.almuhasab.colabdesktoprunner`
**الإصدار:** 1.0.0

تطبيق أندرويد آمن يعمل كواجهة مخصصة لتشغيل سكربت سطح المكتب داخل Google Colab:
- فتح Google Colab عبر **المتصفح الرسمي (Custom Tab)** لتسجيل دخول Google آمن ورسمي.
- اختيار ملف Python من الهاتف عبر **Storage Access Framework** (بدون أذونات تخزين).
- نسخ كود التشغيل الجاهز إلى الحافظة بضغطة واحدة.
- متصفح **WebView داخلي مخصص** لرابط سطح المكتب المؤقت (HTTPS فقط) مع وضع السحب الدقيق.
- **مساعد التشغيل** خطوة بخطوة تحت تحكم المستخدم الكامل.

---

## ⚠️ ملاحظات صادقة وهامة

- **تسجيل دخول Google داخل WebView ممنوع من Google** (خطأ `disallowed_useragent`). لذلك المسار الافتراضي والرسمي هو **Custom Tab** — وهو المتصفح الرسمي داخل تجربة التطبيق.
- **جلسة Google في Custom Tab لا تنتقل إلى WebView الداخلي** — هذا سلوك أمني من أندرويد ولا يدّعي التطبيق عكس ذلك.
- التطبيق **لا يتجاوز CAPTCHA** ولا قيود Colab، ولا ينفذ أي نقر أو رفع أو تشغيل تلقائي.
- رابط سطح المكتب (مثل trycloudflare.com) **مؤقت** ويتغير عند إعادة تشغيل الجلسة.
- جلسات Colab قد تتوقف وفق سياسات Google.

---

## فتح المشروع

المشروع مشروع Flutter (Dart + طبقة Kotlin أصلية في `android/`):

```bash
# المتطلبات: Flutter 3.35.x، JDK 17، Android SDK (API 35)
flutter pub get
```

- افتح المجلد في Android Studio أو VS Code.
- كود Kotlin الأصلي: `android/app/src/main/kotlin/com/almuhasab/colabdesktoprunner/MainActivity.kt`
- كود Dart: `lib/` (معمارية MVVM: core / models / services / viewmodels / screens).

## البناء

```bash
# APK للاختبار (Debug)
flutter build apk --debug

# APK نهائي موقع (Release)
flutter build apk --release

# حزمة AAB لمتجر Google Play
flutter build appbundle --release
```

المخرجات:
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

## التوقيع

التوقيع مُعدّ في `android/app/build.gradle.kts` ويقرأ من `android/key.properties`:

```properties
storeFile=../release-key.jks
storePassword=<كلمة مرور المخزن>
keyAlias=release
keyPassword=<كلمة مرور المفتاح>
```

لإنشاء مفتاح جديد خاص بك:

```bash
keytool -genkey -v -keystore release-key.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias release
```

> **لا تضع كلمات المرور داخل الكود أو داخل Git.**

## تثبيت APK

1. انقل `app-release.apk` إلى هاتفك.
2. فعّل "تثبيت من مصادر غير معروفة" لتطبيق مدير الملفات.
3. اضغط على الملف واتبع التعليمات.
4. أو عبر ADB: `adb install app-release.apk`

---

## استخدام التطبيق

### 1) اختيار السكربت
- من الشاشة الرئيسية اضغط **"اختيار ملف السكربت"**.
- تُفتح نافذة الملفات الرسمية (SAF) — اختر ملف `.py` أو `.txt` أو `.ipynb`.
- يظهر اسم الملف وحجمه في بطاقة **"آخر ملف مختار"** ويُحفظ المرجع بعد إعادة التشغيل.

### 2) فتح Colab
- اضغط **"فتح Google Colab"** — يُفتح في المتصفح الرسمي (Custom Tab).
- سجّل الدخول بحساب Google بشكل رسمي. التطبيق لا يطّلع على كلمة المرور.
- **"فتح دفتر جديد"** ينشئ Notebook جديدًا.

### 3) نسخ كود التشغيل
- اضغط **"نسخ كود التشغيل"** — يُنسخ الكود التالي إلى الحافظة:

```python
from google.colab import files
from pathlib import Path

uploaded = files.upload()
if not uploaded:
    raise RuntimeError("لم يتم اختيار أي ملف.")

filename = next(iter(uploaded))
path = Path("/content") / filename
print(f"تشغيل الملف: {path.name}")
get_ipython().run_line_magic("run", f'-i "{path}"')
```

- في Colab: أنشئ خلية → الصق → اضغط تشغيل (▶) بنفسك → اختر ملف Python عند ظهور نافذة الرفع.

### 4) فتح رابط سطح المكتب
- عندما يطبع السكربت رابط سطح المكتب (مثل `https://xxx.trycloudflare.com`)، انسخه.
- افتح شاشة **"سطح المكتب"** في التطبيق → الصق الرابط → **"فتح سطح المكتب"**.
- يتحقق التطبيق من أن الرابط **HTTPS** ويعرض اسم النطاق لموافقتك قبل الفتح.
- داخل المتصفح: شريط أدوات قابل للطي (تحديث، إعادة اتصال، السحب الدقيق، ملاءمة الشاشة، نسخ الرابط، فتح خارجي).
- **وضع السحب الدقيق**: يحوّل حركة إصبعك إلى سحب بزر الفأرة الأيسر مع 3 مستويات حساسية (من الإعدادات). زر الرجوع يخرج من الوضع.
- عند انقطاع الاتصال: إعادة محاولة تلقائية بتدرج 2، 5، 10، 20 ثانية ثم تتوقف — مع زر "إعادة المحاولة الآن".

### مساعد التشغيل
وضع إرشادي يعرض 8 مراحل واحدة تلو الأخرى (اختيار الملف → فتح Colab → نسخ الكود → اللصق → التشغيل → الرفع → انتظار الرابط → فتح سطح المكتب)، مع علامة إنجاز يحددها المستخدم وزر تنفيذ لكل مرحلة قابلة للتنفيذ. **لا يوجد أي تنفيذ تلقائي.**

---

## الأذونات وسبب استخدامها

| الإذن | السبب |
|---|---|
| `INTERNET` | الوصول إلى Google Colab ورابط سطح المكتب (HTTPS فقط) |

**لا يطلب التطبيق:**
- ❌ أذونات تخزين (`READ/WRITE_EXTERNAL_STORAGE`, `MANAGE_EXTERNAL_STORAGE`) — يُستخدم SAF فقط.
- ❌ `QUERY_ALL_PACKAGES`
- ❌ AccessibilityService
- ❌ أي إذن كاميرا/موقع/جهات اتصال

## الخصوصية والأمان

- لا تحليلات، لا Telemetry، لا Firebase، لا إعلانات.
- لا يتم تسجيل كلمات مرور أو Cookies أو Tokens، ولا تظهر في السجلات.
- `android:usesCleartextTraffic="false"` + `network_security_config` يمنعان أي HTTP غير مشفر.
- لا يتم تجاوز أخطاء SSL أبدًا (سلوك WebView الافتراضي: إيقاف الاتصال).
- بيانات WebView مستثناة من النسخ الاحتياطي التلقائي (`backup_rules.xml`, `data_extraction_rules.xml`).
- R8/ProGuard مفعّل لإصدار Release مع إزالة استدعاءات Log.
- الإعدادات غير الحساسة فقط تُخزن محليًا (SharedPreferences).
- زر "نسخ تفاصيل الخطأ" يخفي Cookies وTokens وquery parameters الحساسة.

## الاختبارات

```bash
flutter test        # 22 اختبارًا
flutter analyze     # لا أخطاء (تنبيهات deprecation فقط لـ RadioListTile)
```

تغطي الاختبارات: التحقق من HTTPS ورفض HTTP، كود التشغيل، الاحتفاظ بمرجع الملف بعد إعادة التشغيل، أسماء الملفات العربية والمسافات، عدم تخزين بيانات حساسة، شاشة الخصوصية، الشاشة الرئيسية وRTL، تأكيد النطاق قبل الفتح، مساعد التشغيل، تدرج إعادة الاتصال.
