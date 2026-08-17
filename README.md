# colab-desktop-runner

مشروع تشغيل سطح مكتب لينكس على Google Colab مع وصول MCP عبر Cloudflare، وحفظ الحالة في Google Drive، وتشغيل Chrome و GenSpark و Cursor و Antigravity IDE و Android Studio.

> الملف الحالي الرئيسي: `colab_desktop_v59_app_zoom_lowlatency_v29.py`

## الإصدار الحالي

**V29 / v59** — تكبير التطبيقات + بث منخفض التأخير للهاتف + إصلاح منفذ CDP لوكيل Qwen.

### التحقق الساكن

- `python3 -m py_compile`: ناجح
- إصلاح وكيل Qwen: توحيد منفذ CDP إلى `9224`
- راجع التقرير التفصيلي: [`reports/REPORT_V29_QWEN_CDP_FIX.md`](reports/REPORT_V29_QWEN_CDP_FIX.md)
- راجع سجل التطوير الكامل: [`reports/PROJECT_HISTORY_V15_TO_V29.md`](reports/PROJECT_HISTORY_V15_TO_V29.md)

## طريقة الاستخدام في Colab

ارفع الملف التالي إلى جلسة Colab:

- `colab_desktop_v59_app_zoom_lowlatency_v29.py`

ثم شغّله في خلية Colab:

```python
from google.colab import drive
drive.mount('/content/drive')

path = "/content/colab_desktop_v59_app_zoom_lowlatency_v29.py"
%run -i "{path}"
```

عند اكتمال الإقلاع سيظهر رابط سطح المكتب / MCP داخل مخرجات الخلية.

## المحتويات

```text
colab_desktop_v59_app_zoom_lowlatency_v29.py   # الكود الحديث الرئيسي
reports/                                        # تقارير المهام والإصلاحات
patches/                                        # ملفات patch الموثقة
CHECKSUMS-SHA256.txt                            # بصمات SHA-256 للملفات الأساسية
```

## اختبار سريع بعد الإقلاع

```bash
ss -ltnp | grep -E '9223|9224|8790' || true
curl -s http://127.0.0.1:9224/json/list | head || true
curl -s http://127.0.0.1:8790/health || true
```

المتوقع:

- Chrome debugging على `127.0.0.1:9224`
- جسر Qwen على `127.0.0.1:8790`

## ملاحظة أمان

لا تضع أي رمز مميز أو كلمة مرور داخل الملفات أو سجلات الكود. جميع المفاتيح الحساسة يجب إدخالها من داخل الجلسة أو تخزينها في ملفات صلاحيات مقفلة داخل Colab.
