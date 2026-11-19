package com.zoren.pickle_arena

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Many Android phones drop UDP broadcast packets unless a multicast lock is
    // held. The lobby needs them to discover rooms on the same Wi-Fi / hotspot.
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pickle_arena/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        try {
                            if (multicastLock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                multicastLock = wifi.createMulticastLock("pickle_arena").apply {
                                    setReferenceCounted(false)
                                }
                            }
                            multicastLock?.acquire()
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "releaseMulticastLock" -> {
                        releaseLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun releaseLock() {
        try {
            if (multicastLock?.isHeld == true) multicastLock?.release()
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }
}
