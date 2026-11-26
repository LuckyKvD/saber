package com.adilhanney.saber

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import java.io.File

/// Feder-Schnellnotiz: Widget mit Vorschau der ersten Seite der Notiz
/// "Schnellnotiz". Ein Tipp öffnet Feder direkt in dieser Notiz.
class QuickNoteWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    companion object {
        const val ACTION_QUICK_NOTE = "de.luckykvd.feder.QUICK_NOTE"
        private const val PREVIEW_FILE = "quicknote_preview.png"
        private const val MAX_WIDTH = 720

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.quick_note_widget)
            val bitmap = loadPreview(context)
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.quick_note_preview, bitmap)
                views.setViewVisibility(R.id.quick_note_preview, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.quick_note_hint, android.view.View.GONE)
            } else {
                views.setViewVisibility(R.id.quick_note_preview, android.view.View.GONE)
                views.setViewVisibility(R.id.quick_note_hint, android.view.View.VISIBLE)
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                action = ACTION_QUICK_NOTE
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pending = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.quick_note_root, pending)
            return views
        }

        private fun loadPreview(context: Context): Bitmap? {
            return try {
                val file = File(context.filesDir, PREVIEW_FILE)
                if (!file.exists()) return null
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, bounds)
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= MAX_WIDTH) sample *= 2
                BitmapFactory.decodeFile(
                    file.absolutePath,
                    BitmapFactory.Options().apply { inSampleSize = sample }
                )
            } catch (e: Throwable) {
                null
            }
        }

        /// Schreibt die Vorschau (PNG) in den privaten App-Speicher und
        /// aktualisiert alle Widgets. `png == null` löscht die Vorschau.
        fun setPreview(context: Context, png: ByteArray?) {
            val file = File(context.filesDir, PREVIEW_FILE)
            try {
                if (png == null) file.delete() else file.writeBytes(png)
            } catch (e: Throwable) {
            }
            refresh(context)
        }

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, QuickNoteWidget::class.java))
            for (id in ids) manager.updateAppWidget(id, buildViews(context))
        }
    }
}
