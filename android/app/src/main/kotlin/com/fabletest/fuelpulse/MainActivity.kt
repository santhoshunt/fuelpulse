package com.fabletest.fuelpulse

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "fuelpulse/update"
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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updateInstaller?.dispose()
        updateInstaller = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
