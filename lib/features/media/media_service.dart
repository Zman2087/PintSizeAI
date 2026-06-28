import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Bridges to MediaPlugin.swift for:
///   - Image understanding (Vision scene/OCR/face analysis)
///   - Background removal (iOS 17+ VNGenerateForegroundInstanceMask)
///   - PDF text extraction (PDFKit)
///   - Generic text extraction (txt, csv, rtf, docx, html)
class MediaService {
  static const _method = MethodChannel('pintsize/media');

  Future<String?> analyzeImage(Uint8List bytes) async {
    try {
      return await _method.invokeMethod<String>('analyzeImage', {'bytes': bytes});
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> removeBackground(Uint8List bytes) async {
    final result = await _method.invokeMethod<Uint8List>('removeBackground', {
      'bytes': bytes,
    });
    if (result == null) throw Exception('No result from removeBackground');
    return result;
  }

  Future<String?> extractPDF(String path) async {
    try {
      return await _method.invokeMethod<String>('extractPDF', {'path': path});
    } on PlatformException catch (e) {
      if (e.code == 'NO_TEXT') return null;
      rethrow;
    }
  }

  /// Extract text from .txt, .csv, .tsv, .md, .json, .rtf, .html, .docx files.
  Future<String?> extractText(String path) async {
    try {
      return await _method.invokeMethod<String>('extractText', {'path': path});
    } on PlatformException catch (e) {
      if (e.code == 'NO_TEXT') return null;
      return null;
    }
  }
}
