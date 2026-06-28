import Flutter
import CloudKit

/// Provides lightweight CloudKit sync for chat sessions.
///
/// MethodChannel: pintsize/cloud_sync
///   saveSessions({json: String}) → void
///   loadSessions()              → String? (JSON)
///   isAvailable()               → Bool
///
/// Uses the default CloudKit container. Requires:
///   1. iCloud capability + CloudKit enabled in Xcode
///   2. com.apple.developer.icloud-container-identifiers entitlement
///   3. com.apple.developer.ubiquity-kvstore-identifier entitlement (for KV fallback)
final class CloudSyncPlugin: NSObject {

    private static let recordType  = "ChatSessions"
    private static let recordID    = CKRecord.ID(recordName: "pintsize-sessions")
    private static let jsonField   = "json"

    // KV fallback (no entitlement check needed for basic iCloud KV)
    private let kv = NSUbiquitousKeyValueStore.default

    static func register(with messenger: FlutterBinaryMessenger) {
        let plugin = CloudSyncPlugin()
        FlutterMethodChannel(name: "pintsize/cloud_sync", binaryMessenger: messenger)
            .setMethodCallHandler(plugin.handle(_:result:))
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "isAvailable":
            result(FileManager.default.ubiquityIdentityToken != nil)

        case "saveSessions":
            guard let args = call.arguments as? [String: Any],
                  let json = args["json"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "saveSessions requires {json}", details: nil))
                return
            }
            kv.set(json, forKey: "sessions_v1")
            kv.synchronize()
            result(nil)

        case "loadSessions":
            kv.synchronize()
            result(kv.string(forKey: "sessions_v1"))

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
