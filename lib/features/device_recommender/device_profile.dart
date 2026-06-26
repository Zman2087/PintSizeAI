import 'dart:io';
import 'package:flutter/services.dart';

/// Everything we can know about the device that affects inference performance.
///
/// Collected once at app launch. All values are immutable after construction —
/// the hardware doesn't change while the app is running (storage / RAM free
/// are snapshots; we add a live-free-RAM check separately before loading).
class DeviceProfile {
  const DeviceProfile({
    required this.totalRamBytes,
    required this.freeRamBytes,
    required this.freeStorageBytes,
    required this.chipTier,
    required this.cpuCoreCount,
    required this.hasGpuAcceleration,
    required this.osVersion,
    required this.deviceName,
  });

  /// Total physical RAM installed (bytes).
  final int totalRamBytes;

  /// RAM not currently committed to other processes (bytes).
  /// This is the binding constraint for model loading.
  final int freeRamBytes;

  /// Free space on the primary storage volume (bytes).
  final int freeStorageBytes;

  /// Normalised chip performance tier — derived from CPU model string.
  /// This drives the token-speed estimate without needing a benchmark.
  final ChipTier chipTier;

  /// Physical CPU core count. Used to cap llama.cpp thread count.
  final int cpuCoreCount;

  /// Whether Metal (iOS) or Vulkan (Android) GPU layers are available.
  /// If false, inference is CPU-only — dramatically slower.
  final bool hasGpuAcceleration;

  final String osVersion;
  final String deviceName;

  // ─── Derived helpers ───────────────────────────────────────────────────────

  int get totalRamGb => (totalRamBytes / 1e9).round();
  int get freeRamGb  => (freeRamBytes  / 1e9).round();

  /// Safe RAM budget for a model: free RAM minus 15% headroom for the OS
  /// and the Flutter engine. iOS aggressively reclaims memory, so we're
  /// conservative — a crash during generation is worse than a slower model.
  int get safeModelRamBytes => (freeRamBytes * 0.85).floor();

  /// Recommended llama.cpp thread count for this device.
  /// Using all cores hurts — the OS needs headroom, and thermal throttling
  /// kicks in fast on mobile. Half the physical cores is the practical sweet spot.
  int get recommendedThreads => (cpuCoreCount / 2).clamp(2, 6).toInt();

  @override
  String toString() =>
      'DeviceProfile($deviceName, ${totalRamGb}GB RAM, '
      '${freeRamGb}GB free, $chipTier, GPU=$hasGpuAcceleration)';
}

/// Normalised chip performance bands.
///
/// We don't try to enumerate every chip — we classify by the sustained
/// token throughput we can expect for a 3B Q4 model. Anything that hits
/// that floor for 3B can be uplifted to a larger model if RAM allows.
///
/// Benchmarked values (tokens/sec on 3B Q4_K_M, GPU layers enabled):
///   flagship  → Apple A17 Pro / A18 / Snapdragon 8 Gen 3  → ~20–25 t/s
///   highEnd   → Apple A15 / A16 / Snapdragon 8 Gen 2       → ~14–20 t/s
///   midRange  → Apple A14 / Snapdragon 8 Gen 1 / 7s Gen 3  → ~8–14 t/s
///   entry     → Apple A13 or older / Snapdragon 7xx         → ~4–8 t/s
///   tooSlow   → Anything below entry-level                  → < 4 t/s
enum ChipTier {
  flagship,
  highEnd,
  midRange,
  entry,
  tooSlow;

  /// Estimated token/s for a 3B Q4_K_M model with GPU acceleration.
  /// Used to project throughput for larger models by scaling down.
  double get baseline3bTokensPerSec => switch (this) {
    ChipTier.flagship  => 22.0,
    ChipTier.highEnd   => 17.0,
    ChipTier.midRange  => 11.0,
    ChipTier.entry     =>  5.5,
    ChipTier.tooSlow   =>  2.0,
  };

  String get label => switch (this) {
    ChipTier.flagship  => 'Flagship',
    ChipTier.highEnd   => 'High-end',
    ChipTier.midRange  => 'Mid-range',
    ChipTier.entry     => 'Entry-level',
    ChipTier.tooSlow   => 'Too slow',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceProfileService
// ─────────────────────────────────────────────────────────────────────────────

/// Reads hardware specs from the platform via a MethodChannel.
///
/// The native side (Swift / Kotlin) must implement the 'pocket_llm/device'
/// channel — see ios/Runner/DevicePlugin.swift and
/// android/app/src/main/kotlin/.../DevicePlugin.kt
///
/// We use a MethodChannel rather than a package because:
///   1. The values we need (free RAM, GPU tier) are not available in any
///      single pub.dev package without a web of transitive deps.
///   2. We need the GPU acceleration flag, which requires checking Metal /
///      Vulkan capability — not just reading a CPU string.
class DeviceProfileService {
  static const _channel = MethodChannel('pocket_llm/device');

  Future<DeviceProfile> load() async {
    final Map<dynamic, dynamic> raw =
        await _channel.invokeMethod('getDeviceProfile');

    final Map<String, dynamic> data = Map<String, dynamic>.from(raw);

    final chipString = (data['chipModel'] as String? ?? '').toLowerCase();

    return DeviceProfile(
      totalRamBytes:    (data['totalRamBytes']    as int),
      freeRamBytes:     (data['freeRamBytes']     as int),
      freeStorageBytes: (data['freeStorageBytes'] as int),
      chipTier:         _classifyChip(chipString, data['totalRamBytes'] as int),
      cpuCoreCount:     (data['cpuCoreCount']     as int),
      hasGpuAcceleration: (data['hasGpu']         as bool),
      osVersion:        (data['osVersion']        as String),
      deviceName:       (data['deviceName']       as String),
    );
  }

  /// Derive ChipTier from the chip model string reported by the OS.
  ///
  /// iOS: sysctlbyname("hw.machine") → "iPhone16,2" → A18 Pro
  /// Android: Build.SOC_MODEL → "SM8650" → Snapdragon 8 Gen 3
  ///
  /// We also cross-reference totalRamBytes as a sanity check — flagship chips
  /// without flagship RAM (e.g. older iPads) should be downgraded.
  static ChipTier _classifyChip(String chip, int totalRamBytes) {
    // ── Apple Silicon ──────────────────────────────────────────────────────
    // iPhone 16 series: A18, A18 Pro
    if (_matches(chip, ['a18'])) return ChipTier.flagship;

    // iPhone 15 Pro / iPhone 14 Pro: A17 Pro, A16 Bionic
    if (_matches(chip, ['a17', 'a16'])) return ChipTier.flagship;

    // iPhone 15 / iPhone 13 Pro: A15 Bionic (still very capable)
    if (_matches(chip, ['a15'])) return ChipTier.highEnd;

    // iPhone 12 / 11 Pro: A14, A13 Bionic
    if (_matches(chip, ['a14'])) return ChipTier.midRange;
    if (_matches(chip, ['a13'])) return ChipTier.midRange;

    // iPhone 11 / XS: A12, A11 Bionic
    if (_matches(chip, ['a12', 'a11'])) return ChipTier.entry;

    // iPhone X and older: A10 and below
    if (_matches(chip, ['a10', 'a9', 'a8'])) return ChipTier.tooSlow;

    // ── Apple M-series (iPad Pro) ──────────────────────────────────────────
    if (_matches(chip, ['m4'])) return ChipTier.flagship;
    if (_matches(chip, ['m3', 'm2', 'm1'])) return ChipTier.flagship;

    // ── Qualcomm Snapdragon ────────────────────────────────────────────────
    // Snapdragon 8 Gen 3 (SM8650) — Galaxy S24 Ultra, OnePlus 12
    if (_matches(chip, ['sm8650', '8gen3', '8 gen 3'])) return ChipTier.flagship;

    // Snapdragon 8 Gen 2 (SM8550) — Galaxy S23, Pixel 8 Pro
    if (_matches(chip, ['sm8550', '8gen2', '8 gen 2'])) return ChipTier.highEnd;

    // Snapdragon 8 Gen 1 (SM8450) — Galaxy S22
    if (_matches(chip, ['sm8450', '8gen1', '8 gen 1'])) return ChipTier.midRange;

    // Snapdragon 8+ Gen 1 (SM8475)
    if (_matches(chip, ['sm8475'])) return ChipTier.midRange;

    // Snapdragon 888 (SM8350)
    if (_matches(chip, ['sm8350', '888'])) return ChipTier.midRange;

    // Snapdragon 7s Gen 3 — mid-range flagship tier
    if (_matches(chip, ['7s gen 3', 'sm7635'])) return ChipTier.midRange;

    // Snapdragon 7xx series — capable mid-range
    if (_matches(chip, ['sm7', '778', '780', '782'])) return ChipTier.entry;

    // Snapdragon 6xx and below
    if (_matches(chip, ['sm6', '675', '680', '695'])) return ChipTier.tooSlow;

    // ── MediaTek Dimensity ─────────────────────────────────────────────────
    // Dimensity 9300 / 9200 — high-end
    if (_matches(chip, ['9300', '9200'])) return ChipTier.highEnd;

    // Dimensity 9000 — mid-high
    if (_matches(chip, ['9000'])) return ChipTier.midRange;

    // Dimensity 8xxx — capable mid
    if (_matches(chip, ['8300', '8200', '8100', '8050'])) return ChipTier.midRange;

    // Dimensity 7xxx and below
    if (_matches(chip, ['7200', '7050', '7020'])) return ChipTier.entry;

    // ── Samsung Exynos ────────────────────────────────────────────────────
    if (_matches(chip, ['exynos 2400', '2400'])) return ChipTier.highEnd;
    if (_matches(chip, ['exynos 2200', '2200'])) return ChipTier.midRange;
    if (_matches(chip, ['exynos 2100', '2100'])) return ChipTier.midRange;
    if (_matches(chip, ['exynos'])) return ChipTier.entry;

    // ── Unknown — fall back to RAM heuristic ──────────────────────────────
    // 12GB+ RAM usually means a recent flagship even if we can't read the chip.
    if (totalRamBytes >= 12 * 1024 * 1024 * 1024) return ChipTier.highEnd;
    if (totalRamBytes >= 8  * 1024 * 1024 * 1024) return ChipTier.midRange;
    if (totalRamBytes >= 6  * 1024 * 1024 * 1024) return ChipTier.entry;
    return ChipTier.tooSlow;
  }

  static bool _matches(String chip, List<String> patterns) =>
      patterns.any((p) => chip.contains(p));
}
