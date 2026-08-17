#!/bin/bash
set -e
export ANDROID_HOME=/root/Android/Sdk
export ANDROID_SDK_ROOT=/root/Android/Sdk
PROJ=/root/agent-workspaces/qwen/photo-editor
rm -rf "$PROJ"
mkdir -p "$PROJ/app/src/main/java/com/example/photoeditor"
mkdir -p "$PROJ/app/src/main/res/layout" "$PROJ/app/src/main/res/values" "$PROJ/app/src/main/res/drawable" "$PROJ/app/src/main/res/mipmap-anydpi-v26"
cd "$PROJ"
cat > settings.gradle <<'X'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "PhotoEditor"
include ':app'
X
cat > build.gradle <<'X'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
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
    buildTypes {
        release { minifyEnabled false }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
X
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
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
X
cat > app/src/main/res/values/strings.xml <<'X'
<resources>
    <string name="app_name">معدل الصور</string>
</resources>
X
cat > app/src/main/res/values/colors.xml <<'X'
<resources>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="teal_200">#FF03DAC5</color>
</resources>
X
cat > app/src/main/res/values/themes.xml <<'X'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.PhotoEditor" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorSecondary">@color/teal_200</item>
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
    android:orientation="vertical" android:padding="16dp" android:gravity="center_horizontal"
    android:background="#111111">
    <TextView
        android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:text="@string/app_name" android:textColor="#FFFFFF"
        android:textSize="24sp" android:paddingBottom="12dp"/>
    <Button android:id="@+id/btnPick"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="اختر صورة"/>
    <Button android:id="@+id/btnGray"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="تدرج رمادي"/>
    <Button android:id="@+id/btnSave"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="حفظ الصورة"/>
    <ImageView android:id="@+id/image"
        android:layout_width="match_parent" android:layout_height="0dp"
        android:layout_weight="1" android:scaleType="fitCenter"
        android:background="#222222" android:contentDescription="الصورة المعدلة"/>
</LinearLayout>
X
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
    private static final int PICK_IMAGE = 1001;
    private ImageView image;
    private Bitmap currentBitmap;
    private Bitmap originalBitmap;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        image = findViewById(R.id.image);
        Button pick = findViewById(R.id.btnPick);
        Button gray = findViewById(R.id.btnGray);
        Button save = findViewById(R.id.btnSave);
        pick.setOnClickListener(v -> pickImage());
        gray.setOnClickListener(v -> applyGrayscale());
        save.setOnClickListener(v -> saveImage());
    }

    private void pickImage() {
        Intent intent = new Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI);
        intent.setType("image/*");
        startActivityForResult(intent, PICK_IMAGE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == PICK_IMAGE && resultCode == RESULT_OK && data != null && data.getData() != null) {
            try {
                InputStream is = getContentResolver().openInputStream(data.getData());
                originalBitmap = BitmapFactory.decodeStream(is);
                if (originalBitmap != null) {
                    currentBitmap = originalBitmap.copy(Bitmap.Config.ARGB_8888, true);
                    image.setImageBitmap(currentBitmap);
                } else {
                    toast("تعذر قراءة الصورة");
                }
            } catch (Exception e) {
                toast("خطأ: " + e.getMessage());
            }
        }
    }

    private void applyGrayscale() {
        if (originalBitmap == null) { toast("اختر صورة أولًا"); return; }
        Bitmap out = Bitmap.createBitmap(originalBitmap.getWidth(), originalBitmap.getHeight(), Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(out);
        ColorMatrix matrix = new ColorMatrix();
        matrix.setSaturation(0);
        paint.setColorFilter(new ColorMatrixColorFilter(matrix));
        canvas.drawBitmap(originalBitmap, 0, 0, paint);
        currentBitmap = out;
        image.setImageBitmap(currentBitmap);
        toast("تم تطبيق التدرج الرمادي");
    }

    private void saveImage() {
        if (currentBitmap == null) { toast("لا توجد صورة للحفظ"); return; }
        try {
            String name = "photo_editor_" + System.currentTimeMillis() + ".png";
            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DISPLAY_NAME, name);
            values.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PhotoEditor");
                values.put(MediaStore.Images.Media.IS_PENDING, 1);
            }
            Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
            if (uri == null) { toast("تعذر الإنشاء في المعرض"); return; }
            try (OutputStream os = getContentResolver().openOutputStream(uri)) {
                currentBitmap.compress(Bitmap.CompressFormat.PNG, 100, os);
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear();
                values.put(MediaStore.Images.Media.IS_PENDING, 0);
                getContentResolver().update(uri, values, null, null);
            }
            toast("تم حفظ الصورة في المعرض");
        } catch (Exception e) {
            toast("فشل الحفظ: " + e.getMessage());
        }
    }

    private void toast(String m) {
        Toast.makeText(this, m, Toast.LENGTH_LONG).show();
    }
}
X
if [ ! -x gradlew ]; then
  if [ ! -d /opt/gradle-8.7 ]; then
    wget -q https://services.gradle.org/distributions/gradle-8.7-bin.zip -O /tmp/gradle-8.7-bin.zip
    unzip -q -o /tmp/gradle-8.7-bin.zip -d /opt
  fi
  /opt/gradle-8.7/bin/gradle wrapper --gradle-version 8.7 --no-daemon
fi
chmod +x gradlew
echo "=== BUILD START $(date -u +%H:%M:%S) ==="
./gradlew assembleDebug --no-daemon --stacktrace 2>&1 | tail -80
echo "=== BUILD DONE rc=$? ==="
ls -la app/build/outputs/apk/debug/
cp app/build/outputs/apk/debug/app-debug.apk /root/Desktop/photo-editor.apk
ls -la /root/Desktop/photo-editor.apk
unzip -t /root/Desktop/photo-editor.apk >/tmp/apk_verify.txt 2>&1 && echo "UNZIP_OK lines=$(wc -l </tmp/apk_verify.txt)" || (cat /tmp/apk_verify.txt; exit 1)
/root/Android/Sdk/build-tools/34.0.0/aapt dump badging /root/Desktop/photo-editor.apk 2>/dev/null | head -8
echo "=== ALL DONE ==="
