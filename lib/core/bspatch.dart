import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// تطبيق رقعة بصيغة BSDIFF40 القياسية (نفس صيغة أداة bsdiff الأصلية
/// ومكتبة bsdiff4 المستخدمة في CI) — تنفيذ Dart خالص قابل للاختبار.
///
/// بنية الملف:
/// - 8 بايت: التوقيع "BSDIFF40"
/// - 8 بايت: طول كتلة التحكم المضغوطة (bzip2)
/// - 8 بايت: طول كتلة الفروقات المضغوطة (bzip2)
/// - 8 بايت: حجم الملف الناتج
/// - ثم: كتلة التحكم + كتلة الفروقات + كتلة الإضافات (كلها bzip2)
class BsPatch {
  static const _magic = 'BSDIFF40';

  /// فك ترميز offtin (عدد 64-بت بإشارة بترميز bsdiff الخاص).
  static int _offtin(Uint8List b, int off) {
    int y = b[off + 7] & 0x7F;
    for (int i = 6; i >= 0; i--) {
      y = y * 256 + b[off + i];
    }
    if ((b[off + 7] & 0x80) != 0) y = -y;
    return y;
  }

  /// تطبيق [patch] على [oldData] وإرجاع الملف الجديد.
  /// يرمي [FormatException] عند أي تلف في الرقعة.
  static Uint8List apply(Uint8List oldData, Uint8List patch) {
    if (patch.length < 32) {
      throw const FormatException('رقعة قصيرة جدًا');
    }
    final magic = String.fromCharCodes(patch.sublist(0, 8));
    if (magic != _magic) {
      throw const FormatException('توقيع رقعة غير صالح (ليست BSDIFF40)');
    }
    final ctrlLen = _offtin(patch, 8);
    final diffLen = _offtin(patch, 16);
    final newSize = _offtin(patch, 24);
    if (ctrlLen < 0 || diffLen < 0 || newSize < 0) {
      throw const FormatException('أطوال رقعة غير صالحة');
    }
    // حد أمان: لا نسمح بملف ناتج أكبر من 300 ميغابايت
    if (newSize > 300 * 1024 * 1024) {
      throw const FormatException('حجم الملف الناتج يتجاوز الحد المسموح');
    }
    if (32 + ctrlLen + diffLen > patch.length) {
      throw const FormatException('رقعة مبتورة');
    }

    final dec = BZip2Decoder();
    final ctrl = Uint8List.fromList(
        dec.decodeBytes(patch.sublist(32, 32 + ctrlLen)));
    final diff = Uint8List.fromList(BZip2Decoder()
        .decodeBytes(patch.sublist(32 + ctrlLen, 32 + ctrlLen + diffLen)));
    final extra = Uint8List.fromList(
        BZip2Decoder().decodeBytes(patch.sublist(32 + ctrlLen + diffLen)));

    final out = Uint8List(newSize);
    int oldPos = 0, newPos = 0, ctrlPos = 0, diffPos = 0, extraPos = 0;

    while (newPos < newSize) {
      if (ctrlPos + 24 > ctrl.length) {
        throw const FormatException('كتلة تحكم مبتورة');
      }
      final addLen = _offtin(ctrl, ctrlPos);
      final copyLen = _offtin(ctrl, ctrlPos + 8);
      final seekLen = _offtin(ctrl, ctrlPos + 16);
      ctrlPos += 24;

      if (addLen < 0 ||
          newPos + addLen > newSize ||
          diffPos + addLen > diff.length) {
        throw const FormatException('كتلة فروقات تالفة');
      }
      // دمج الفروقات مع البيانات القديمة
      for (int i = 0; i < addLen; i++) {
        int v = diff[diffPos + i];
        if (oldPos + i >= 0 && oldPos + i < oldData.length) {
          v = (v + oldData[oldPos + i]) & 0xFF;
        }
        out[newPos + i] = v;
      }
      newPos += addLen;
      oldPos += addLen;
      diffPos += addLen;

      if (copyLen < 0 ||
          newPos + copyLen > newSize ||
          extraPos + copyLen > extra.length) {
        throw const FormatException('كتلة إضافات تالفة');
      }
      out.setRange(newPos, newPos + copyLen, extra, extraPos);
      newPos += copyLen;
      extraPos += copyLen;

      oldPos += seekLen;
    }
    return out;
  }

  /// تطبيق رقعة على ملف قديم وكتابة الناتج إلى ملف — نسخة مخفّضة الذاكرة
  /// للأجهزة الضعيفة:
  /// - الملف القديم يُقرأ من القرص عبر [RandomAccessFile] (لا يُحمَّل كاملًا).
  /// - الناتج يُكتب تدفقيًا إلى [outPath] (لا يُحتفظ به في الذاكرة).
  /// - القيد المتبقي: كتل الرقعة المفكوكة (ctrl/diff/extra) تبقى في الذاكرة
  ///   لأن فك bzip2 في Dart غير تدفقي — الذروة ≈ حجم الناتج بدل ‎3×‎ حجمه.
  ///
  /// يتحقق من المساحة الحرة قبل البدء، ويحذف الملف المؤقت عند أي فشل.
  static Future<void> applyToFile({
    required String oldPath,
    required Uint8List patch,
    required String outPath,
    int? maxNewSize,
    int freeSpaceMargin = 64 * 1024 * 1024,
  }) async {
    if (patch.length < 32) {
      throw const FormatException('رقعة قصيرة جدًا');
    }
    final magic = String.fromCharCodes(patch.sublist(0, 8));
    if (magic != _magic) {
      throw const FormatException('توقيع رقعة غير صالح (ليست BSDIFF40)');
    }
    final ctrlLen = _offtin(patch, 8);
    final diffLen = _offtin(patch, 16);
    final newSize = _offtin(patch, 24);
    if (ctrlLen < 0 || diffLen < 0 || newSize < 0) {
      throw const FormatException('أطوال رقعة غير صالحة');
    }
    final cap = maxNewSize ?? 300 * 1024 * 1024;
    if (newSize > cap) {
      throw const FormatException('حجم الملف الناتج يتجاوز الحد المسموح');
    }
    if (32 + ctrlLen + diffLen > patch.length) {
      throw const FormatException('رقعة مبتورة');
    }

    // فحص المساحة الحرة قبل البدء (best effort — statvfs غير متاح في Dart،
    // نحاول الكتابة المسبقة للحجم المطلوب بدلًا من ذلك).
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);

    RandomAccessFile? oldRaf;
    RandomAccessFile? outRaf;
    try {
      final ctrl = Uint8List.fromList(
          BZip2Decoder().decodeBytes(patch.sublist(32, 32 + ctrlLen)));
      final diff = Uint8List.fromList(BZip2Decoder()
          .decodeBytes(patch.sublist(32 + ctrlLen, 32 + ctrlLen + diffLen)));
      final extra = Uint8List.fromList(
          BZip2Decoder().decodeBytes(patch.sublist(32 + ctrlLen + diffLen)));

      oldRaf = await File(oldPath).open();
      final oldLen = await oldRaf.length();
      outRaf = await outFile.open(mode: FileMode.write);
      // حجز المساحة مقدمًا — يفشل مبكرًا إن كانت المساحة غير كافية.
      await outRaf.truncate(newSize);
      await outRaf.setPosition(0);

      const chunk = 256 * 1024;
      int oldPos = 0, newPos = 0, ctrlPos = 0, diffPos = 0, extraPos = 0;

      while (newPos < newSize) {
        if (ctrlPos + 24 > ctrl.length) {
          throw const FormatException('كتلة تحكم مبتورة');
        }
        final addLen = _offtin(ctrl, ctrlPos);
        final copyLen = _offtin(ctrl, ctrlPos + 8);
        final seekLen = _offtin(ctrl, ctrlPos + 16);
        ctrlPos += 24;

        if (addLen < 0 ||
            newPos + addLen > newSize ||
            diffPos + addLen > diff.length) {
          throw const FormatException('كتلة فروقات تالفة');
        }
        // دمج الفروقات مع القديم على دفعات صغيرة
        int done = 0;
        while (done < addLen) {
          final n = (addLen - done) < chunk ? (addLen - done) : chunk;
          final buf = Uint8List(n);
          buf.setRange(0, n, diff, diffPos + done);
          final readStart = oldPos + done;
          if (readStart < oldLen) {
            final readEnd =
                (readStart + n) < oldLen ? (readStart + n) : oldLen;
            await oldRaf.setPosition(readStart);
            final oldChunk = await oldRaf.read(readEnd - readStart);
            for (int i = 0; i < oldChunk.length; i++) {
              buf[i] = (buf[i] + oldChunk[i]) & 0xFF;
            }
          }
          await outRaf.writeFrom(buf);
          done += n;
        }
        newPos += addLen;
        oldPos += addLen;
        diffPos += addLen;

        if (copyLen < 0 ||
            newPos + copyLen > newSize ||
            extraPos + copyLen > extra.length) {
          throw const FormatException('كتلة إضافات تالفة');
        }
        if (copyLen > 0) {
          await outRaf.writeFrom(extra, extraPos, extraPos + copyLen);
        }
        newPos += copyLen;
        extraPos += copyLen;
        oldPos += seekLen;
      }
      await outRaf.flush();
    } catch (_) {
      // فشل التحقق/الترقيع: احذف الملف المؤقت فقط — لا مساس بأي شيء آخر.
      try {
        await outRaf?.close();
        outRaf = null;
      } catch (_) {}
      if (await outFile.exists()) {
        try {
          await outFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      try {
        await oldRaf?.close();
      } catch (_) {}
      try {
        await outRaf?.close();
      } catch (_) {}
    }
  }
}
