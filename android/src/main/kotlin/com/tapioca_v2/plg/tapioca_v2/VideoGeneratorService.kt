package com.tapioca_v2.plg.tapioca_v2

import android.app.Activity
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
    override fun writeVideofile(processing: HashMap<String,HashMap<String,Any>>, result: Result, activity: Activity, eventSink: EventChannel.EventSink ) {
        val filters: MutableList<GlFilter> = mutableListOf()
        // Track timed image overlay filters so we can update their time
        val timedImageFilters: MutableList<GlImageOverlayFilter> = mutableListOf()

        try {
            processing.forEach { (k, v) ->
                // Strip index suffix (e.g. "ImageOverlay_1" → "ImageOverlay")
                // to support multiple overlays of the same type.
                val baseKey = if (k.contains("_") && k.last().isDigit()) {
                    k.substringBeforeLast("_")
                } else k

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
                        val filter = GlImageOverlayFilter(imageOverlay)
                        if (imageOverlay.hasTiming) {
                            timedImageFilters.add(filter)
                        }
                        filters.add(filter)
                    }
                }
            }
        } catch (e: Exception){
            println(e)
            activity.runOnUiThread(Runnable {
                result.error("processing_data_invalid", "Processing data is invalid.", null)
            })
        }
        composer.filter(GlFilterGroup( filters))
            .videoFormatMimeType(VideoFormatMimeType.MPEG4)
            .listener(object : Mp4Composer.Listener {
                override fun onProgress(progress: Double) {
                    println("onProgress = $progress")
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
                    println(exception);
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
