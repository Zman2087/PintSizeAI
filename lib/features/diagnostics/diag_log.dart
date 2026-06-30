import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight append-only diagnostic logger that writes to a file in the app
/// documents directory. Used because release-mode print() does not surface in
/// `flutter logs`. Pull with:
///   xcrun devicectl device copy from --domain-type appDataContainer \
///     --domain-identifier com.pintsize.ai --source Documents/pintsize_diag.log ...
class DiagLog {
  static const _fileName = 'pintsize_diag.log';
  static File? _file;

  static Future<File> _resolve() async {
    if (_file != null) return _file!;
    final docs = await getApplicationDocumentsDirectory();
    _file = File(p.join(docs.path, _fileName));
    return _file!;
  }

  static Future<void> log(String line) async {
    try {
      final f = await _resolve();
      final ts = DateTime.now().toIso8601String();
      await f.writeAsString('$ts  $line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // never throw from diagnostics
    }
  }
}
