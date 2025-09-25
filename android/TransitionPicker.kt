package com.tapes.player

import com.tapes.model.TransitionStyle
import java.util.Random

object TransitionPicker {
    fun sequenceForTape(tapeId: String, boundaries: Int): List<TransitionStyle> {
        val seed = tapeId.hashCode().toLong()
        val rng = Random(seed)
        val pool = listOf(TransitionStyle.None, TransitionStyle.Crossfade, TransitionStyle.SlideLR, TransitionStyle.SlideRL)
        return List(boundaries.coerceAtLeast(0)) { pool[rng.nextInt(pool.size)] }
    }
    fun clampedDuration(requested: Double): Double = minOf(requested, 0.5)
}
