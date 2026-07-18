package com.ientier.i_entier

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "i_entier/phone").setMethodCallHandler { call, result ->
            if (call.method != "dial") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val number = call.argument<String>("number")
            if (number.isNullOrBlank()) {
                result.error("INVALID_NUMBER", "Phone number is required.", null)
                return@setMethodCallHandler
            }

            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))
            if (intent.resolveActivity(packageManager) == null) {
                result.error("NO_DIALER", "No phone dialer is available.", null)
                return@setMethodCallHandler
            }

            startActivity(intent)
            result.success(null)
        }
    }
}
