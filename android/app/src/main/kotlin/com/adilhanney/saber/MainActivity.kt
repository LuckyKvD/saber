package com.adilhanney.saber

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
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
    // Feder-Schnellnotiz-Widget: Start über das Widget merken bzw. an Dart melden.
    private var quickNotePending = false
    private var widgetChannel: MethodChannel? = null

    // Feder-Fotoauswahl: Galerie, Google Fotos, Ente; Bilder werden nativ verkleinert.
    private var photoResult: MethodChannel.Result? = null
    private var photoMaxSize = 2048
    private var cameraFile: File? = null
    private val photoLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { res ->
        val result = photoResult
        photoResult = null
        if (result != null) handlePhotoResult(result, res.resultCode, res.data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerCryptoChannel(flutterEngine)
        registerPhotoChannel(flutterEngine)
        registerWidgetChannel(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.luckykvd.feder/ink")
            .setMethodCallHandler { call, result ->
                if (call.method == "recognize") {
                    val lang = call.argument<String>("language") ?: "de"
                    @Suppress("UNCHECKED_CAST")
                    val strokes = call.argument<List<List<List<Double>>>>("strokes")
                    if (strokes == null) {
                        result.error("bad_args", "Striche fehlen", null)
                    } else {
                        InkRecognizer.recognize(lang, strokes, result)
                    }
                } else {
                    result.notImplemented()
                }
            }
        // Feder: Blaettergeraeusch (res/raw/page_flip.wav)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.luckykvd.feder/sound")
            .setMethodCallHandler { call, result ->
                if (call.method == "pageFlip") {
                    try {
                        val id = resources.getIdentifier("page_flip", "raw", packageName)
                        if (id != 0) {
                            val player = android.media.MediaPlayer.create(this, id)
                            player?.setOnCompletionListener { it.release() }
                            player?.start()
                        }
                    } catch (e: Throwable) {}
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
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

    private fun registerWidgetChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.luckykvd.feder/widget")
        widgetChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeLaunchAction" -> {
                    val pending = quickNotePending
                    quickNotePending = false
                    result.success(pending)
                }
                "setPreview" -> {
                    QuickNoteWidget.setPreview(applicationContext, call.arguments as? ByteArray)
                    result.success(null)
                }
                "setColor" -> {
                    val color = (call.arguments as? Number)?.toInt()
                    if (color != null) QuickNoteWidget.setColor(applicationContext, color)
                    result.success(null)
                }
                "clearPreview" -> {
                    QuickNoteWidget.setPreview(applicationContext, null)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleWidgetIntent(intent: Intent?) {
        if (intent?.action == QuickNoteWidget.ACTION_QUICK_NOTE) {
            quickNotePending = true
            intent.action = null
            widgetChannel?.invokeMethod("quickNote", null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun registerPhotoChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.luckykvd.feder/photos")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (photoResult != null) {
                    result.error("busy", "Auswahl läuft bereits", null)
                    return@setMethodCallHandler
                }
                val source = call.argument<String>("source") ?: "system"
                photoMaxSize = call.argument<Int>("maxSize") ?: 2048
                val pkg = when (source) {
                    "google" -> "com.google.android.apps.photos"
                    "ente" -> "io.ente.photos"
                    else -> null
                }
                val intent = if (source == "camera") {
                    val dir = File(cacheDir, "camera").apply { mkdirs() }
                    val file = File(dir, "cam_${System.nanoTime()}.jpg")
                    cameraFile = file
                    val uri = FileProvider.getUriForFile(this, "$packageName.federprovider", file)
                    Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                        .putExtra(MediaStore.EXTRA_OUTPUT, uri)
                        .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } else if (source == "system" && Build.VERSION.SDK_INT >= 33) {
                    Intent(MediaStore.ACTION_PICK_IMAGES).putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 30)
                } else {
                    Intent(Intent.ACTION_GET_CONTENT)
                        .setType("image/*")
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
                if (pkg != null) intent.setPackage(pkg)
                try {
                    photoResult = result
                    photoLauncher.launch(intent)
                } catch (e: ActivityNotFoundException) {
                    photoResult = null
                    result.error("not_installed", "App nicht gefunden oder ohne Bildauswahl", null)
                } catch (e: SecurityException) {
                    photoResult = null
                    result.error("not_installed", "App nicht erreichbar", null)
                }
            }
    }

    private fun handlePhotoResult(result: MethodChannel.Result, code: Int, data: Intent?) {
        val camFile = cameraFile
        cameraFile = null
        if (camFile != null) {
            if (code != Activity.RESULT_OK || !camFile.exists() || camFile.length() == 0L) {
                camFile.delete()
                result.success(emptyList<Map<String, Any>>())
                return
            }
            Thread {
                val out = ArrayList<Map<String, Any>>()
                try {
                    val item = decodePhoto(Uri.fromFile(camFile), photoMaxSize)
                    if (item != null) out.add(item)
                } catch (e: Throwable) {}
                camFile.delete()
                runOnUiThread { result.success(out) }
            }.start()
            return
        }
        if (code != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else if (data.data != null) {
            uris.add(data.data!!)
        }
        Thread {
            val out = ArrayList<Map<String, Any>>()
            for (uri in uris) {
                try {
                    val item = decodePhoto(uri, photoMaxSize)
                    if (item != null) out.add(item)
                } catch (e: Throwable) {
                    // einzelnes Bild überspringen
                }
            }
            runOnUiThread { result.success(out) }
        }.start()
    }

    // Verkleinert mit Sample-Size (schnell), dreht nach EXIF und schreibt JPEG (oder PNG bei Transparenz).
    private fun decodePhoto(uri: Uri, maxSize: Int): Map<String, Any>? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSize) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        } ?: return null

        var orientation = ExifInterface.ORIENTATION_NORMAL
        try {
            contentResolver.openInputStream(uri)?.use {
                orientation = ExifInterface(it).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
                )
            }
        } catch (e: Throwable) {}

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.postScale(-1f, 1f) }
        }
        val longest = maxOf(decoded.width, decoded.height)
        if (longest > maxSize) {
            val f = maxSize.toFloat() / longest
            matrix.postScale(f, f)
        }
        val bmp = if (matrix.isIdentity) decoded
            else Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)

        val mime = contentResolver.getType(uri) ?: ""
        val png = bmp.hasAlpha() && (mime.contains("png") || mime.contains("webp") || mime.contains("gif"))
        val file = File(cacheDir, "feder_photo_${System.nanoTime()}.${if (png) "png" else "jpg"}")
        FileOutputStream(file).use {
            if (png) bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
            else bmp.compress(Bitmap.CompressFormat.JPEG, 90, it)
        }
        return mapOf(
            "path" to file.absolutePath,
            "width" to bmp.width,
            "height" to bmp.height,
            "ext" to if (png) ".png" else ".jpg",
        )
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
        handleWidgetIntent(intent)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.isAppearanceLightNavigationBars = true
    }
}
