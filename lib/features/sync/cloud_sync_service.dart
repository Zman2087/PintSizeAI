import 'package:flutter/services.dart';

/// Thin wrapper around CloudSyncPlugin.swift.
/// Uses iCloud KV Store (NSUbiquitousKeyValueStore) to sync sessions.
/// Requires iCloud capability in the Xcode project — works without it
/// but silently no-ops (isAvailable returns false).
class CloudSyncService {
  static const _ch = MethodChannel('pintsize/cloud_sync');

  Future<bool> isAvailable() async {
    try {
      return await _ch.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Save [sessions] JSON string to iCloud KV.
  Future<void> save(String json) async {
    try {
      await _ch.invokeMethod<void>('saveSessions', {'json': json});
    } catch (_) {}
  }

  /// Load sessions JSON string from iCloud KV. Returns null if none.
  Future<String?> load() async {
    try {
      return await _ch.invokeMethod<String?>('loadSessions');
    } catch (_) {
      return null;
    }
  }
}
