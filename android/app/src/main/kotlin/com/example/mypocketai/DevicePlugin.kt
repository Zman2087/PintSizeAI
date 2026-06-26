package com.example.mypocketai

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DevicePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "pocket_llm/device"

        fun register(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(DevicePlugin(context))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceProfile" -> result.success(buildProfile())
            else -> result.notImplemented()
        }
    }

    private fun buildProfile(): Map<String, Any> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)

        return mapOf(
            "totalRamBytes"    to memInfo.totalMem,
            "freeRamBytes"     to memInfo.availMem,
            "freeStorageBytes" to freeStorage(),
            "chipModel"        to chipModel(),
            "cpuCoreCount"     to Runtime.getRuntime().availableProcessors(),
            "hasGpu"           to true, // Vulkan available on Android 7+
            "osVersion"        to "Android ${Build.VERSION.RELEASE}",
            "deviceName"       to "${Build.MANUFACTURER} ${Build.MODEL}",
        )
    }

    private fun freeStorage(): Long {
        val stat = StatFs(Environment.getDataDirectory().path)
        return stat.availableBlocksLong * stat.blockSizeLong
    }

    private fun chipModel(): String {
        // Build.SOC_MODEL available on Android 12+
        val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL
        } else {
            Build.HARDWARE
        }
        return soc.ifBlank { Build.HARDWARE }
    }
}
