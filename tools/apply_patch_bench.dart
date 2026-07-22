// ignore_for_file: avoid_print — أداة قياس سطر أوامر وليست كود إنتاج
import 'dart:io';
import 'dart:typed_data';
import 'package:colab_desktop_runner/core/bspatch.dart';

Future<void> main(List<String> args) async {
  final oldPath = args[0], patchPath = args[1], outPath = args[2];
  final patch = Uint8List.fromList(await File(patchPath).readAsBytes());
  final sw = Stopwatch()..start();
  await BsPatch.applyToFile(
    oldPath: oldPath,
    patch: patch,
    outPath: outPath,
    maxNewSize: 300 * 1024 * 1024,
  );
  sw.stop();
  print('patch applied in ${sw.elapsedMilliseconds} ms, out size=${File(outPath).lengthSync()}');
}
