// android/app/src/main/kotlin/com/pocketllm/app/DevicePlugin.kt
//
// Native platform channel implementation for Android.
// Registers 'pocket_llm/device' and returns hardware specs.
//
// Register in MainActivity.kt:
//   DevicePlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)

package com.mypocketai.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DevicePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

  companion object {
    private const val CHANNEL = "pocket_llm/device"

    fun register(messenger: BinaryMessenger, context: Context) {
      val channel = MethodChannel(messenger, CHANNEL)
      channel.setMethodCallHandler(DevicePlugin(context))
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getDeviceProfile" -> result.success(buildProfile())
      else               -> result.notImplemented()
    }
  }

  // ── Profile builder ──────────────────────────────────────────────────────

  private fun buildProfile(): Map<String, Any> {
    return mapOf(
      "totalRamBytes"    to totalRam(),
      "freeRamBytes"     to freeRam(),
      "freeStorageBytes" to freeStorage(),
      "chipModel"        to chipModel(),
      "cpuCoreCount"     to Runtime.getRuntime().availableProcessors(),
      "hasGpu"           to hasVulkan(),
      "osVersion"        to "Android ${Build.VERSION.RELEASE}",
      "deviceName"       to "${Build.MANUFACTURER} ${Build.MODEL}",
    )
  }

  // ── RAM ──────────────────────────────────────────────────────────────────

  private fun totalRam(): Long {
    val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val info = ActivityManager.MemoryInfo()
    am.getMemoryInfo(info)
    return info.totalMem
  }

  private fun freeRam(): Long {
    val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val info = ActivityManager.MemoryInfo()
    am.getMemoryInfo(info)
    // availMem is what Android considers usable without paging.
    // We subtract 200MB as a safety margin for the kernel and daemons.
    val safety = 200L * 1024L * 1024L
    return (info.availMem - safety).coerceAtLeast(0L)
  }

  // ── Storage ──────────────────────────────────────────────────────────────

  private fun freeStorage(): Long {
    return try {
      val stat = StatFs(Environment.getDataDirectory().path)
      stat.availableBlocksLong * stat.blockSizeLong
    } catch (e: Exception) {
      0L
    }
  }

  // ── Chip identification ──────────────────────────────────────────────────

  /// Returns a chip model string that Dart's _classifyChip() can parse.
  ///
  /// Android exposes Build.SOC_MODEL (API 31+) for the SoC model string.
  /// On older APIs we fall back to Build.HARDWARE which is less reliable
  /// but often contains the chipset name (e.g. "kona" for Snapdragon 865).
  private fun chipModel(): String {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      // API 31+: SOC_MODEL gives us the authoritative chip identifier
      // e.g. "SM8650", "MT6895", "Exynos 2400"
      Build.SOC_MODEL.ifEmpty { legacyChipHeuristic() }
    } else {
      legacyChipHeuristic()
    }
  }

  /// Fallback chip identification for Android < 12.
  /// Cross-references multiple Build fields to make a best guess.
  private fun legacyChipHeuristic(): String {
    // Build.HARDWARE often contains values like "qcom" (Qualcomm),
    // "exynos" (Samsung), "mt6889" (MediaTek). Not as precise as SOC_MODEL
    // but enough for our tier classification.
    val hardware = Build.HARDWARE.lowercase()
    val board    = Build.BOARD.lowercase()

    // Qualcomm identifiers
    if (hardware.contains("qcom") || board.contains("sm8")) {
      return board.uppercase() // e.g. "SM8650"
    }

    // Samsung Exynos
    if (hardware.contains("exynos") || board.contains("exynos")) {
      return "Exynos ${Build.HARDWARE.filter { it.isDigit() }}"
    }

    // MediaTek
    if (hardware.contains("mt") || board.contains("mt")) {
      return board.uppercase()
    }

    // Last resort: return the hardware string and let the Dart heuristic
    // classify by RAM size
    return "${Build.HARDWARE} ${Build.BOARD}"
  }

  // ── GPU / Vulkan ─────────────────────────────────────────────────────────

  /// Returns true if Vulkan 1.0 or higher is available.
  ///
  /// We check the Vulkan feature flag rather than trying to init a Vulkan
  /// context — that would add significant launch latency.
  ///
  /// All Android devices API 28+ are required to support Vulkan 1.1,
  /// but we check explicitly because some low-end devices claim API 28
  /// compliance without real GPU compute support.
  private fun hasVulkan(): Boolean {
    return context.packageManager.hasSystemFeature(
      "android.hardware.vulkan.version"
    )
  }
}
