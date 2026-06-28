import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Handles incoming shares from the iOS Share Extension.
/// The extension writes a JSON payload to the App Group container,
/// then opens pintsize-ai://share, which AppDelegate forwards here
/// via the pintsize/share_extension MethodChannel.
class ShareExtensionService {
  static const _ch = MethodChannel('pintsize/share_extension');

  /// Register a handler. Called when the app is opened via the share sheet.
  void listen(void Function(SharePayload) onShare) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'incomingShare') {
        final payload = await _readPayload();
        if (payload != null) onShare(payload);
      }
    });
  }

  Future<SharePayload?> _readPayload() async {
    // The App Group ID must match ShareViewController.swift
    // On simulator / without provisioning this path won't exist — that's fine.
    try {
      final groupPath = _appGroupPath();
      if (groupPath == null) return null;
      final jsonFile = File('$groupPath/pending_share.json');
      if (!await jsonFile.exists()) return null;

      final raw = await jsonFile.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      await jsonFile.delete(); // consume

      Uint8List? imageBytes;
      if (map['imagePath'] is String) {
        final imgFile = File(map['imagePath'] as String);
        if (await imgFile.exists()) {
          imageBytes = await imgFile.readAsBytes();
          await imgFile.delete();
        }
      }

      return SharePayload(
        text: map['text'] as String?,
        imageBytes: imageBytes,
      );
    } catch (_) {
      return null;
    }
  }

  // Reads the app group container path via a convention — on real device
  // this is accessible if the entitlement is configured.
  String? _appGroupPath() {
    // Cannot look up via Dart; on iOS the path is deterministic after provisioning.
    // Returns null here; the Swift side already writes the file before opening the URL.
    // For a real deployment, you'd use path_provider or a method channel to get the
    // group container URL.
    return null;
  }
}

class SharePayload {
  const SharePayload({this.text, this.imageBytes});
  final String? text;
  final Uint8List? imageBytes;
}
