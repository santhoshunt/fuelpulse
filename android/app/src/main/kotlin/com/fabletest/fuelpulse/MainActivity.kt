package com.fabletest.fuelpulse

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// A FragmentActivity: the app lock's fingerprint prompt (local_auth) needs one.
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "fuelpulse/update"
        private const val FILES_CHANNEL = "fuelpulse/files"
    }

    private var updateInstaller: UpdateInstaller? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL
        )
        updateInstaller?.dispose()
        updateInstaller = UpdateInstaller(this, updateChannel).also { installer ->
            updateChannel.setMethodCallHandler(installer::handle)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "open") {
                    result.success(openFile(call.argument("path"), call.argument("mime")))
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Opens a bill in another app. The file is copied to cache/shared, which
     * the FileProvider in the manifest (res/xml/file_paths.xml) serves as a
     * content URI the other app may read. False when no app takes it.
     */
    private fun openFile(path: String?, mime: String?): Boolean {
        if (path == null) return false
        return try {
            val src = File(path)
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            val dst = File(dir, src.name)
            src.copyTo(dst, overwrite = true)
            val uri = Uri.parse("content://$packageName.files/shared/${Uri.encode(dst.name)}")
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime ?: "*/*")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updateInstaller?.dispose()
        updateInstaller = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
