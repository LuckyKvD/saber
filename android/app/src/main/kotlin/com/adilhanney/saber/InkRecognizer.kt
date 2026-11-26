package com.adilhanney.saber

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.recognition.Ink
import io.flutter.plugin.common.MethodChannel

/**
 * Feder: Handschrift-Erkennung auf dem Gerät (ML Kit Digital Ink Recognition).
 * Die Erkennung selbst läuft ohne Netz. Nur das Sprachmodell (ca. 20 MB) wird
 * beim allerersten Mal geladen.
 */
object InkRecognizer {
    /**
     * [strokes]: Liste von Strichen, jeder Strich eine Liste von [x, y, t].
     * Antwort: Liste der Erkennungs-Kandidaten (bester zuerst).
     */
    fun recognize(
        languageTag: String,
        strokes: List<List<List<Double>>>,
        rawResult: MethodChannel.Result,
    ) {
        var replied = false
        val result = object : MethodChannel.Result {
            override fun success(value: Any?) {
                if (!replied) { replied = true; rawResult.success(value) }
            }
            override fun error(code: String, message: String?, details: Any?) {
                if (!replied) { replied = true; rawResult.error(code, message, details) }
            }
            override fun notImplemented() {
                if (!replied) { replied = true; rawResult.notImplemented() }
            }
        }
        val identifier = try {
            DigitalInkRecognitionModelIdentifier.fromLanguageTag(languageTag)
        } catch (e: Exception) {
            null
        }
        if (identifier == null) {
            result.error("no_model", "Kein Sprachmodell für $languageTag", null)
            return
        }
        val model = DigitalInkRecognitionModel.builder(identifier).build()
        val manager = RemoteModelManager.getInstance()

        val inkBuilder = Ink.builder()
        for (stroke in strokes) {
            val sb = Ink.Stroke.builder()
            for (p in stroke) {
                if (p.size < 3) continue
                sb.addPoint(Ink.Point.create(p[0].toFloat(), p[1].toFloat(), p[2].toLong()))
            }
            inkBuilder.addStroke(sb.build())
        }
        val ink = inkBuilder.build()

        fun run() {
            val recognizer = DigitalInkRecognition.getClient(
                DigitalInkRecognizerOptions.builder(model).build()
            )
            recognizer.recognize(ink)
                .addOnSuccessListener { r ->
                    try {
                        result.success(r.candidates.map { it.text })
                    } catch (t: Throwable) {
                        result.error("recognize_failed", t.toString(), null)
                    }
                    recognizer.close()
                }
                .addOnFailureListener { e ->
                    result.error("recognize_failed", e.toString(), null)
                    recognizer.close()
                }
        }

        manager.isModelDownloaded(model)
            .addOnSuccessListener { downloaded ->
                if (downloaded) {
                    run()
                } else {
                    manager.download(model, DownloadConditions.Builder().build())
                        .addOnSuccessListener { run() }
                        .addOnFailureListener { e ->
                            result.error(
                                "download_failed",
                                "Sprachmodell konnte nicht geladen werden (Internet nötig, einmalig): $e",
                                null,
                            )
                        }
                }
            }
            .addOnFailureListener { e -> result.error("model_check_failed", e.toString(), null) }
    }
}
