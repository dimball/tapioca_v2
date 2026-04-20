package com.tapioca_v2.plg.tapioca_v2

import android.app.Activity
import android.util.Log
import com.daasuu.mp4compose.composer.Mp4Composer
import com.daasuu.mp4compose.filter.*
import com.tapioca_v2.plg.tapioca_v2.filter.GlImageOverlayFilter
import io.flutter.plugin.common.MethodChannel.Result
import com.daasuu.mp4compose.VideoFormatMimeType
import io.flutter.plugin.common.EventChannel
import com.tapioca_v2.plg.tapioca_v2.filter.GlColorBlendFilter
import com.tapioca_v2.plg.tapioca_v2.filter.GlTextOverlayFilter

interface VideoGeneratorServiceInterface {
    fun writeVideofile(processing: HashMap<String,HashMap<String,Any>>, result: Result, activity: Activity, eventSink: EventChannel.EventSink);
    fun cancelExport(result: Result);

}

class VideoGeneratorService(
    private val composer: Mp4Composer
) : VideoGeneratorServiceInterface {
    companion object {
        private const val TAG = "VideoGeneratorService"
    }

    override fun writeVideofile(processing: HashMap<String,HashMap<String,Any>>, result: Result, activity: Activity, eventSink: EventChannel.EventSink ) {
        val filters: MutableList<GlFilter> = mutableListOf()
        // Track timed image overlay filters so we can update their time
        val timedImageFilters: MutableList<GlImageOverlayFilter> = mutableListOf()

        Log.d(TAG, "writeVideofile: ${processing.size} processing entries")

        try {
            processing.forEach { (k, v) ->
                // Strip index suffix (e.g. "ImageOverlay_1" → "ImageOverlay")
                // to support multiple overlays of the same type.
                val baseKey = if (k.contains("_") && k.last().isDigit()) {
                    k.substringBeforeLast("_")
                } else k

                Log.d(TAG, "Processing entry '$k' (baseKey='$baseKey')")

                when (baseKey) {
                    "Filter" -> {
                        val passFilter = Filter(v)
                        val filter = GlColorBlendFilter(passFilter)
                        filters.add(filter)
                    }
                    "TextOverlay" -> {
                        val textOverlay = TextOverlay(v)
                        filters.add(GlTextOverlayFilter(textOverlay))
                    }
                    "ImageOverlay" -> {
                        val imageOverlay = ImageOverlay(v)
                        val bitmapSize = imageOverlay.bitmap.size
                        Log.d(TAG, "ImageOverlay '$k': bitmap=${bitmapSize} bytes, " +
                            "pos=(${imageOverlay.x}, ${imageOverlay.y}), " +
                            "hasTiming=${imageOverlay.hasTiming}" +
                            if (imageOverlay.hasTiming)
                                ", start=${imageOverlay.startMs}ms, end=${imageOverlay.endMs}ms, " +
                                "fadeIn=${imageOverlay.fadeInMs}ms, fadeOut=${imageOverlay.fadeOutMs}ms"
                            else "")
                        val filter = GlImageOverlayFilter(imageOverlay)
                        if (imageOverlay.hasTiming) {
                            timedImageFilters.add(filter)
                        }
                        filters.add(filter)
                    }
                }
            }
        } catch (e: Exception){
            Log.e(TAG, "Error parsing processing data: ${e.message}", e)
            activity.runOnUiThread(Runnable {
                result.error("processing_data_invalid", "Processing data is invalid.", null)
            })
        }
        composer.filter(GlFilterGroup( filters))
            .videoFormatMimeType(VideoFormatMimeType.MPEG4)
            .listener(object : Mp4Composer.Listener {
                override fun onProgress(progress: Double) {
                    Log.d(TAG, "onProgress = $progress")
                    activity.runOnUiThread(Runnable {
                        eventSink.success(progress)
                    })
                }

                override fun onCurrentWrittenVideoTime(currentTimeMs: Long) {
                    // Update all timed image overlay filters with current time
                    for (filter in timedImageFilters) {
                        filter.currentTimeMs.set(currentTimeMs)
                    }
                }

                override fun onCompleted() {
                    activity.runOnUiThread(Runnable {
                        result.success(null)
                    })
                }

                override  fun onCanceled() {
                    activity.runOnUiThread(Runnable {
                        result.error("video_processing_canceled", "Video processing is canceled.", null)
                    })
                }

                override fun onFailed(exception: Exception) {
                    Log.e(TAG, "Video processing failed: ${exception.message}", exception)
                    activity.runOnUiThread(Runnable {
                        result.error("video_processing_failed", "video processing is failed.", null)

                    })
                }
            }).start()
    }
    override fun cancelExport(result: Result) {
        composer.cancel()
    }
}
