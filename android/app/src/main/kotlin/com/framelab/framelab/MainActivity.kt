package com.framelab.framelab

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build

class MainActivity : FlutterActivity() {
    private lateinit var media: LocalMediaBridge
    private var pendingExport: Pair<Map<String, Any?>, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        media = LocalMediaBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.framelab/media").setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
            if (call.method == "publish" && Build.VERSION.SDK_INT < 29 && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                if (pendingExport != null) { result.error("BUSY", "Another export is awaiting permission.", null) }
                else {
                    pendingExport = Pair(args, result)
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 2001)
                }
            } else { media.handle(call.method, args, result) }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2001) {
            val request = pendingExport
            pendingExport = null
            if (request != null) {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) media.handle("publish", request.first, request.second)
                else request.second.error("PERMISSION", "Storage permission is needed to save to the gallery on this Android version. Your project remains saved.", null)
            }
        }
    }

    override fun onDestroy() {
        if (::media.isInitialized) media.close()
        pendingExport?.second?.error("CANCELLED", "Export was interrupted. Your project is safe.", null)
        pendingExport = null
        super.onDestroy()
    }
}
