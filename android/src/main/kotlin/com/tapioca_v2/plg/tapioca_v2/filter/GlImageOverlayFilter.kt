package com.tapioca_v2.plg.tapioca_v2.filter

import com.daasuu.mp4compose.filter.GlOverlayFilter;
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import com.tapioca_v2.plg.tapioca_v2.ImageOverlay
import java.util.concurrent.atomic.AtomicLong

class GlImageOverlayFilter(imageOverlay: ImageOverlay) : GlOverlayFilter() {
    private val imageOverlay: ImageOverlay = imageOverlay
    private val decodedBitmap by lazy {
        BitmapFactory.decodeByteArray(imageOverlay.bitmap, 0, imageOverlay.bitmap.size)
    }

    // Shared time tracker updated from onCurrentWrittenVideoTime callback
    val currentTimeMs = AtomicLong(0)

    protected override fun drawCanvas(canvas: Canvas) {
        val bitmap = decodedBitmap ?: return

        val paint: Paint? = if (imageOverlay.hasTiming) {
            val tMs = currentTimeMs.get().toDouble()
            val alpha = computeAlpha(tMs)
            if (alpha <= 0.001) return // Skip drawing if fully transparent
            if (alpha >= 0.999) {
                null // Full opacity, no paint needed
            } else {
                Paint().apply {
                    this.alpha = (alpha * 255).toInt().coerceIn(0, 255)
                }
            }
        } else {
            null // Legacy overlay, always fully opaque
        }

        canvas.drawBitmap(bitmap, imageOverlay.x.toFloat(), imageOverlay.y.toFloat(), paint)
    }

    private fun computeAlpha(tMs: Double): Double {
        val startMs = imageOverlay.startMs
        val endMs = imageOverlay.endMs
        val fadeInMs = imageOverlay.fadeInMs
        val fadeOutMs = imageOverlay.fadeOutMs
        val duration = endMs - startMs

        if (duration <= 0 || tMs < startMs || tMs >= endMs) return 0.0

        val elapsed = tMs - startMs
        val remaining = endMs - tMs
        var alpha = 1.0

        if (fadeInMs > 0 && elapsed < fadeInMs) {
            alpha = elapsed / fadeInMs
        }
        if (fadeOutMs > 0 && remaining < fadeOutMs) {
            val fadeOutAlpha = remaining / fadeOutMs
            alpha = minOf(alpha, fadeOutAlpha)
        }
        alpha = alpha.coerceIn(0.0, 1.0)

        // Smoothstep easing
        if (alpha > 0.0 && alpha < 1.0) {
            alpha = alpha * alpha * (3.0 - 2.0 * alpha)
        }
        return alpha
    }
}
