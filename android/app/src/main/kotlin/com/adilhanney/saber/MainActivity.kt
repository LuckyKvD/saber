package com.adilhanney.saber

import android.os.Bundle
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK
import org.bouncycastle.crypto.generators.Argon2BytesGenerator
import org.bouncycastle.crypto.params.Argon2Parameters

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerCryptoChannel(flutterEngine)
        // Feder-App-Sperre: FLAG_SECURE verbirgt den Inhalt in der App-Übersicht.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.luckykvd.feder/secure")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.arguments as? Boolean ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // Feder-Verschlüsselung: Argon2id nativ (Java) statt reinem Dart (20+ Minuten).
    private fun registerCryptoChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.luckykvd.feder/crypto")
            .setMethodCallHandler { call, result ->
                if (call.method == "argon2id") {
                    val password = call.argument<ByteArray>("password")
                    val salt = call.argument<ByteArray>("salt")
                    val memoryKiB = call.argument<Int>("memoryKiB")
                    val iterations = call.argument<Int>("iterations")
                    val parallelism = call.argument<Int>("parallelism")
                    val length = call.argument<Int>("length")
                    if (password == null || salt == null || memoryKiB == null ||
                        iterations == null || parallelism == null || length == null) {
                        result.error("bad_args", "Argon2id: fehlende Argumente", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val params = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
                                .withVersion(Argon2Parameters.ARGON2_VERSION_13)
                                .withIterations(iterations)
                                .withMemoryAsKB(memoryKiB)
                                .withParallelism(parallelism)
                                .withSalt(salt)
                                .build()
                            val generator = Argon2BytesGenerator()
                            generator.init(params)
                            val out = ByteArray(length)
                            generator.generateBytes(password, out)
                            runOnUiThread { result.success(out) }
                        } catch (e: Throwable) {
                            runOnUiThread { result.error("argon2_failed", e.toString(), null) }
                        }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getIntExtra("org.chromium.chrome.extra.TASK_ID", -1) == this.taskId) {
            this.finish()
            intent.addFlags(FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        }
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.isAppearanceLightNavigationBars = true
    }
}
