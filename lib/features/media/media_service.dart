import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Bridges to MediaPlugin.swift for:
///   - Image understanding (Vision scene/OCR/face analysis)
///   - Background removal (iOS 17+ VNGenerateForegroundInstanceMask)
///   - PDF text extraction (PDFKit)
class MediaService {
  static const _method = MethodChannel('pintsize/media');

  /// Analyse an image and return a text description suitable for prepending
  /// to an LLM prompt as context.  Never throws — returns null on failure.
  Future<String?> analyzeImage(Uint8List bytes) async {
    try {
      final result = await _method.invokeMethod<String>('analyzeImage', {
        'bytes': bytes,
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Remove the background from an image. Returns transparent PNG bytes.
  /// Requires iOS 17+. Throws a [PlatformException] with code OS_UNSUPPORTED
  /// on older iOS.
  Future<Uint8List> removeBackground(Uint8List bytes) async {
    final result = await _method.invokeMethod<Uint8List>('removeBackground', {
      'bytes': bytes,
    });
    if (result == null) throw Exception('No result from removeBackground');
    return result;
  }

  /// Extract plain text from a PDF file at [path].
  /// Returns null if the PDF has no extractable text (e.g. scanned image).
  Future<String?> extractPDF(String path) async {
    try {
      return await _method.invokeMethod<String>('extractPDF', {
        'path': path,
      });
    } on PlatformException catch (e) {
      if (e.code == 'NO_TEXT') return null;
      rethrow;
    }
  }
}
