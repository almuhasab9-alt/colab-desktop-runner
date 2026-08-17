# colab-desktop-runner

مشروع تشغيل سطح مكتب لينكس على Google Colab مع وصول MCP عبر Cloudflare، وحفظ الحالة في Google Drive، وتشغيل Chrome و GenSpark و Cursor و Antigravity IDE و Android Studio.

> الملف الحالي الرئيسي: `colab_desktop_v61_qwen_bridge_robust_v31.py`

## الإصدار الحالي

**V31 / v61** — جسر Qwen3.8-Max مقاوم لتغيّر الواجهة، يعمل مع Qwen Chat و Qwen Studio.

### تحقق مباشر على الجلسة الحية (2026-08-17)

- جسر Qwen v3 شغّال على `127.0.0.1:8790`.
- منفذ CDP لـChrome مكتشَف ديناميكيًا (`9224`).
- اختبار فعلي: سؤال «ما عاصمة فرنسا؟» عاد الجواب الصحيح `باريس` عبر الجسر.
- `python3 -m py_compile`: ناجح.

التفاصيل في:
- [`reports/REPORT_V31_QWEN_BRIDGE_ROBUST.md`](reports/REPORT_V31_QWEN_BRIDGE_ROBUST.md)
- [`reports/PROJECT_HISTORY_V15_TO_V31.md`](reports/PROJECT_HISTORY_V15_TO_V31.md)

## طريقة الاستخدام في Colab

ارفع الملف التالي إلى جلسة Colab:

- `colab_desktop_v61_qwen_bridge_robust_v31.py`

ثم شغّله في خلية Colab:

```python
from google.colab import drive
drive.mount('/content/drive')

path = "/content/colab_desktop_v61_qwen_bridge_robust_v31.py"
%run -i "{path}"
```

عند اكتمال الإقلاع سيظهر رابط سطح المكتب / MCP داخل مخرجات الخلية.

## المحتويات

```text
colab_desktop_v61_qwen_bridge_robust_v31.py   # الكود الحديث الرئيسي
reports/                                       # تقارير المهام والإصلاحات
patches/                                       # ملفات patch الموثقة
CHECKSUMS-SHA256.txt                           # بصمات SHA-256 للملفات الأساسية
```

## اختبار سريع بعد الإقلاع

```bash
ss -ltnp | grep -E '8790|922' || true
curl -s http://127.0.0.1:8790/health || true
TOK=$(cat /root/.config/gs-qwen-bridge-token 2>/dev/null)
curl -s -X POST http://127.0.0.1:8790/v1/chat/completions \
  -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  -d '{"model":"Qwen3.8-Max","messages":[{"role":"user","content":"ما عاصمة فرنسا؟ أجب بكلمة واحدة."}]}'
```

## ملاحظة أمان

لا تضع أي رمز مميز أو كلمة مرور داخل الملفات أو سجلات الكود. جميع المفاتيح الحساسة يجب إدخالها من داخل الجلسة أو تخزينها في ملفات صلاحيات مقفلة داخل Colab.
