package com.tapioca_v2.plg.tapioca_v2

import android.graphics.Bitmap

data class Filter(val map: Map<String, Any>) {
    val type: String    by map
    val alpha: Double by map
}

data class ImageOverlay(val map: Map<String, Any>) {
    val bitmap: ByteArray    by map
    val x: Int by map
    val y: Int by map

    // Optional timing params for fade-in/out (not present in legacy overlays)
    val startMs: Double get() = (map["startMs"] as? Number)?.toDouble() ?: 0.0
    val endMs: Double get() = (map["endMs"] as? Number)?.toDouble() ?: 0.0
    val fadeInMs: Double get() = (map["fadeInMs"] as? Number)?.toDouble() ?: 0.0
    val fadeOutMs: Double get() = (map["fadeOutMs"] as? Number)?.toDouble() ?: 0.0
    val hasTiming: Boolean get() = map.containsKey("startMs")
}

data class TextOverlay(val map: Map<String, Any>) {
    val text: String by map
    val x: Int by map
    val y: Int by map
    val size: Int by map
    val color: String by map
}
