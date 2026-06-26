// ios/Runner/DevicePlugin.swift
//
// Native platform channel implementation for iOS.
// Registers the 'pocket_llm/device' channel and returns hardware specs
// that are not accessible from Dart directly.
//
// Install: add this file to ios/Runner/ in Xcode, then register it in
// AppDelegate.swift by calling DevicePlugin.register(with: registrar).

import Flutter
import UIKit
import Metal
import Darwin // for sysctl

class DevicePlugin: NSObject, FlutterPlugin {

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pocket_llm/device",
      binaryMessenger: registrar.messenger()
    )
    let instance = DevicePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDeviceProfile":
      result(buildProfile())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ── Profile builder ──────────────────────────────────────────────────────

  private func buildProfile() -> [String: Any] {
    return [
      "totalRamBytes":    totalRam(),
      "freeRamBytes":     freeRam(),
      "freeStorageBytes": freeStorage(),
      "chipModel":        chipModel(),
      "cpuCoreCount":     ProcessInfo.processInfo.processorCount,
      "hasGpu":           hasMetalGpu(),
      "osVersion":        UIDevice.current.systemVersion,
      "deviceName":       UIDevice.current.name,
    ]
  }

  // ── RAM ──────────────────────────────────────────────────────────────────

  private func totalRam() -> Int {
    return Int(ProcessInfo.processInfo.physicalMemory)
  }

  private func freeRam() -> Int {
    // Query VM statistics from the Mach kernel.
    // This is the same approach used by Activity Monitor and Instruments.
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
    )
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }

    guard result == KERN_SUCCESS else {
      // Fallback: assume 30% free if kernel call fails
      return Int(Double(totalRam()) * 0.30)
    }

    let pageSize = Int(vm_page_size)
    // "Free" from the OS perspective — pages not committed to any process.
    // We deliberately exclude "inactive" pages even though iOS can reclaim
    // them, because the reclaim latency can spike inference start time.
    let freePages = Int(stats.free_count)
    return freePages * pageSize
  }

  // ── Storage ──────────────────────────────────────────────────────────────

  private func freeStorage() -> Int {
    guard let attrs = try? FileManager.default.attributesOfFileSystem(
      forPath: NSHomeDirectory()
    ) else { return 0 }
    return (attrs[.systemFreeSize] as? Int) ?? 0
  }

  // ── Chip identification ──────────────────────────────────────────────────

  /// Returns the chip identifier string used by Dart's _classifyChip().
  /// Examples: "A18 Pro", "A15 Bionic", "M2"
  private func chipModel() -> String {
    // hw.machine gives the device model string, e.g. "iPhone16,2"
    // We map this to the chip name that shipped with each model.
    let machine = sysctlString("hw.machine")
    return chipName(for: machine)
  }

  private func sysctlString(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buffer, &size, nil, 0)
    return String(cString: buffer)
  }

  /// Maps Apple's internal model identifier to the chip name.
  /// Source: theiphonewiki.com/wiki/Models
  private func chipName(for machine: String) -> String {
    let map: [String: String] = [
      // iPhone 16 series — A18 / A18 Pro
      "iPhone17,1": "A18 Pro",
      "iPhone17,2": "A18 Pro",
      "iPhone17,3": "A18",
      "iPhone17,4": "A18",

      // iPhone 15 series
      "iPhone16,1": "A17 Pro",
      "iPhone16,2": "A17 Pro",
      "iPhone15,4": "A16",
      "iPhone15,5": "A16",

      // iPhone 14 series
      "iPhone15,2": "A15 Bionic",
      "iPhone15,3": "A15 Bionic",
      "iPhone14,7": "A15 Bionic",
      "iPhone14,8": "A15 Bionic",

      // iPhone 13 series
      "iPhone14,2": "A15 Bionic",
      "iPhone14,3": "A15 Bionic",
      "iPhone14,4": "A15 Bionic",
      "iPhone14,5": "A15 Bionic",

      // iPhone 12 series
      "iPhone13,1": "A14 Bionic",
      "iPhone13,2": "A14 Bionic",
      "iPhone13,3": "A14 Bionic",
      "iPhone13,4": "A14 Bionic",

      // iPhone 11 series
      "iPhone12,1": "A13 Bionic",
      "iPhone12,3": "A13 Bionic",
      "iPhone12,5": "A13 Bionic",

      // iPad Pro M-series
      "iPad14,3": "M2",
      "iPad14,4": "M2",
      "iPad14,5": "M2",
      "iPad14,6": "M2",
      "iPad16,3": "M4",
      "iPad16,4": "M4",
      "iPad16,5": "M4",
      "iPad16,6": "M4",

      // Simulator
      "x86_64": "Simulator",
      "arm64":  "Simulator",
    ]

    return map[machine] ?? machine
  }

  // ── GPU ──────────────────────────────────────────────────────────────────

  /// Returns true if a Metal-capable GPU is available.
  /// All iPhones since 2013 support Metal, but we check at runtime
  /// because the Simulator may not have a GPU device.
  private func hasMetalGpu() -> Bool {
    return MTLCreateSystemDefaultDevice() != nil
  }
}
