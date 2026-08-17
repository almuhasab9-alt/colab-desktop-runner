#!/bin/bash
# =============================================================================
# سكربت بناء تطبيق "معدل الصور" (APK) من الصفر عبر الترمنل فقط
# يعمل 100% على بيئة Colab (Ubuntu) مع Android SDK مثبت.
# المتطلبات: ANDROID_HOME=/root/Android/Sdk (platforms;android-34, build-tools;34.0.0)
# + JDK 17 (يثبّته السكربت تلقائيًا إن غاب) + إنترنت لتنزيل Gradle/Material.
# الاستخدام:  bash build_photo_editor.sh
# الناتج:    ./app/build/outputs/apk/debug/app-debug.apk
#             ونسخة على ~/Desktop/photo-editor.apk
# =============================================================================
set -e
export ANDROID_HOME=/root/Android/Sdk
export ANDROID_SDK_ROOT=/root/Android/Sdk

# ---- اختيار JDK 17 (إلزامي لتوافق AGP 8.5) ----
J17=$(ls -d /usr/lib/jvm/java-17-openjdk-* 2>/dev/null | head -1)
if [ -z "$J17" ]; then
  echo ">>> تثبيت OpenJDK 17..."
  (apt-get update -y && apt-get install -y openjdk-17-jdk-headless) >/tmp/jdk17.log 2>&1 \
    || (sudo apt-get update -y && sudo apt-get install -y openjdk-17-jdk-headless) >>/tmp/jdk17.log 2>&1
  J17=$(ls -d /usr/lib/jvm/java-17-openjdk-* 2>/dev/null | head -1)
fi
if [ -z "$J17" ]; then echo "❌ تعذّر توفير JDK 17"; exit 1; fi
export JAVA_HOME="$J17"
echo ">>> JAVA_HOME=$JAVA_HOME"
"$JAVA_HOME/bin/java" -version 2>&1 | head -1

# ---- إنشاء المشروع من الصفر ----
PROJ=/root/agent-workspaces/qwen/photo-editor
rm -rf "$PROJ"
mkdir -p "$PROJ/app/src/main/java/com/example/photoeditor"
mkdir -p "$PROJ/app/src/main/res/layout" "$PROJ/app/src/main/res/values" \
         "$PROJ/app/src/main/res/drawable" "$PROJ/app/src/main/res/mipmap-anydpi-v26"
cd "$PROJ"

# local.properties + gradle.properties (مطلوبان لـAGP وAndroidX)
echo "sdk.dir=$ANDROID_HOME" > local.properties
printf 'android.useAndroidX=true\nandroid.enableJetifier=true\norg.gradle.jvmargs=-Xmx2048m\n' > gradle.properties

cat > settings.gradle <<'X'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories { google(); mavenCentral() }
}
rootProject.name = "PhotoEditor"; include ':app'
X
cat > build.gradle <<'X'
plugins { id 'com.android.application' version '8.5.2' apply false }
X
cat > app/build.gradle <<'X'
plugins { id 'com.android.application' }
android {
  namespace 'com.example.photoeditor'
  compileSdk 34
  defaultConfig {
    applicationId "com.example.photoeditor"
    minSdk 24
    targetSdk 34
    versionCode 1
    versionName "1.0"
  }
  compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
  }
}
dependencies { implementation 'com.google.android.material:material:1.12.0' }
X

# ---- AndroidManifest ----
cat > app/src/main/AndroidManifest.xml <<'X'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
  <application
    android:allowBackup="true"
    android:icon="@mipmap/ic_launcher"
    android:label="@string/app_name"
    android:theme="@style/Theme.PhotoEditor">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
X

# ---- Resources ----
cat > app/src/main/res/values/strings.xml <<'X'
<resources><string name="app_name">معدل الصور</string></resources>
X
cat > app/src/main/res/values/colors.xml <<'X'
<resources>
  <color name="p500">#FF6200EE</color>
  <color name="p700">#FF3700B3</color>
  <color name="t200">#FF03DAC5</color>
</resources>
X
cat > app/src/main/res/values/themes.xml <<'X'
<resources xmlns:tools="http://schemas.android.com/tools">
  <style name="Theme.PhotoEditor" parent="Theme.MaterialComponents.DayNight.NoActionBar">
    <item name="colorPrimary">@color/p500</item>
    <item name="colorPrimaryVariant">@color/p700</item>
    <item name="colorSecondary">@color/t200</item>
  </style>
</resources>
X
cat > app/src/main/res/drawable/ic_launcher_background.xml <<'X'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
  <solid android:color="#1565C0"/>
</shape>
X
cat > app/src/main/res/drawable/ic_launcher_foreground.xml <<'X'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
  android:width="108dp" android:height="108dp"
  android:viewportWidth="108" android:viewportHeight="108">
  <path android:fillColor="#FFFFFF"
    android:pathData="M54,28 m-18,0 a18,18 0 1,0 36,0 a18,18 0 1,0 -36,0 M22,82 L40,58 L54,74 L70,54 L86,82 Z"/>
</vector>
X
cat > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'X'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
X
cat > app/src/main/res/layout/activity_main.xml <<'X'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent" android:layout_height="match_parent"
  android:orientation="vertical" android:padding="16dp"
  android:gravity="center_horizontal" android:background="#111111">
  <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
    android:text="@string/app_name" android:textColor="#FFFFFF"
    android:textSize="24sp" android:paddingBottom="12dp"/>
  <Button android:id="@+id/btnPick" android:layout_width="match_parent"
    android:layout_height="wrap_content" android:text="اختر صورة"/>
  <Button android:id="@+id/btnGray" android:layout_width="match_parent"
    android:layout_height="wrap_content" android:text="تدرج رمادي"/>
  <Button android:id="@+id/btnSave" android:layout_width="match_parent"
    android:layout_height="wrap_content" android:text="حفظ الصورة"/>
  <ImageView android:id="@+id/image" android:layout_width="match_parent"
    android:layout_height="0dp" android:layout_weight="1"
    android:scaleType="fitCenter" android:background="#222222"
    android:contentDescription="الصورة"/>
</LinearLayout>
X

# ---- MainActivity.java (اختيار صورة + فلتر رمادي + حفظ في المعرض) ----
cat > app/src/main/java/com/example/photoeditor/MainActivity.java <<'X'
package com.example.photoeditor;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.Toast;

import java.io.InputStream;
import java.io.OutputStream;

public class MainActivity extends Activity {
    private static final int PICK = 1001;
    private ImageView image;
    private Bitmap cur, orig;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(R.layout.activity_main);
        image = findViewById(R.id.image);
        ((Button) findViewById(R.id.btnPick)).setOnClickListener(v -> pick());
        ((Button) findViewById(R.id.btnGray)).setOnClickListener(v -> gray());
        ((Button) findViewById(R.id.btnSave)).setOnClickListener(v -> save());
    }

    private void pick() {
        Intent i = new Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI);
        i.setType("image/*");
        startActivityForResult(i, PICK);
    }

    @Override
    protected void onActivityResult(int rq, int rc, Intent d) {
        super.onActivityResult(rq, rc, d);
        if (rq == PICK && rc == RESULT_OK && d != null && d.getData() != null) {
            try (InputStream is = getContentResolver().openInputStream(d.getData())) {
                orig = BitmapFactory.decodeStream(is);
                if (orig != null) {
                    cur = orig.copy(Bitmap.Config.ARGB_8888, true);
                    image.setImageBitmap(cur);
                } else toast("تعذر قراءة الصورة");
            } catch (Exception e) {
                toast("خطأ: " + e.getMessage());
            }
        }
    }

    private void gray() {
        if (orig == null) { toast("اختر صورة أولًا"); return; }
        Bitmap o = Bitmap.createBitmap(orig.getWidth(), orig.getHeight(), Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(o);
        ColorMatrix m = new ColorMatrix();
        m.setSaturation(0);
        paint.setColorFilter(new ColorMatrixColorFilter(m));
        c.drawBitmap(orig, 0, 0, paint);
        cur = o;
        image.setImageBitmap(cur);
        toast("تم تطبيق التدرج الرمادي");
    }

    private void save() {
        if (cur == null) { toast("لا توجد صورة للحفظ"); return; }
        try {
            String n = "photo_editor_" + System.currentTimeMillis() + ".png";
            ContentValues v = new ContentValues();
            v.put(MediaStore.Images.Media.DISPLAY_NAME, n);
            v.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                v.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PhotoEditor");
                v.put(MediaStore.Images.Media.IS_PENDING, 1);
            }
            Uri u = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
            if (u == null) { toast("تعذر الإنشاء في المعرض"); return; }
            try (OutputStream os = getContentResolver().openOutputStream(u)) {
                cur.compress(Bitmap.CompressFormat.PNG, 100, os);
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                v.clear();
                v.put(MediaStore.Images.Media.IS_PENDING, 0);
                getContentResolver().update(u, v, null, null);
            }
            toast("تم حفظ الصورة في المعرض");
        } catch (Exception e) {
            toast("فشل الحفظ: " + e.getMessage());
        }
    }

    private void toast(String m) { Toast.makeText(this, m, Toast.LENGTH_LONG).show(); }
}
X

# ---- إعداد Gradle wrapper ----
if [ ! -x ./gradlew ]; then
  if [ ! -d /opt/gradle-8.7 ]; then
    echo ">>> تنزيل Gradle 8.7..."
    wget -q https://services.gradle.org/distributions/gradle-8.7-bin.zip -O /tmp/g87.zip
    unzip -q -o /tmp/g87.zip -d /opt
  fi
  /opt/gradle-8.7/bin/gradle wrapper --gradle-version 8.7 --no-daemon
fi
chmod +x gradlew

# ---- البناء ----
echo ">>> بدء البناء..."
./gradlew assembleDebug --no-daemon
echo ">>> البناء اكتمل بنجاح"
ls -la app/build/outputs/apk/debug/

# ---- نسخ الناتج والتحقق ----
mkdir -p /root/Desktop
cp app/build/outputs/apk/debug/app-debug.apk /root/Desktop/photo-editor.apk
unzip -t /root/Desktop/photo-editor.apk | tail -1
"$ANDROID_HOME/build-tools/34.0.0/aapt" dump badging /root/Desktop/photo-editor.apk | head -6
SIZE=$(stat -c%s /root/Desktop/photo-editor.apk)
echo ">>> APK_SIZE_BYTES=$SIZE"
[ "$SIZE" -gt 1000000 ] && echo ">>> حجم APK ممتاز (>1MB)"
echo ">>> FULL_BUILD_SUCCESS"
