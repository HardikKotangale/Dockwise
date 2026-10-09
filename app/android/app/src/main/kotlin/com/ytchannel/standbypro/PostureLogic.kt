package com.ytchannel.standbypro

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * Decides whether the phone is propped up like a bedside clock, from gravity
 * readings. Plain Kotlin (no Android classes) so it is unit-tested on the JVM.
 *
 * Two angles, from the gravity vector (gx, gy along the screen, gz out of it):
 *  - lean: 0 = lying flat, 90 = standing upright (screen vertical)
 *  - roll: 0 = portrait, 90 = landscape (turned on its side)
 */
class PostureLogic(var config: Config = Config()) {
    data class Config(
        val minLeanDeg: Double = 40.0,
        val landscapeOnly: Boolean = true,
        val enterDwellMs: Long = 1500, // must hold the posture this long to start
        val exitDwellMs: Long = 4000, // ...and lose it this long to stop
        val hysteresisDeg: Double = 10.0, // easier to stay than to start
        // Samples arrive about every 200 ms. A silence longer than this is a hole in
        // the data: neither "held" nor "lost" is known, so the dwell timers restart.
        // (TLC found that without this, two samples with a hole between them could
        // satisfy a dwell: spec/PostureLogic.tla, spec/results/PostureLogic_gaps.txt.)
        val maxGapMs: Long = 500,
    )

    data class Reading(val leanDeg: Double, val rollDeg: Double)

    /** True while the phone has been propped up long enough. */
    var active = false
        private set
    private var goodSince: Long? = null
    private var badSince: Long? = null
    private var lastSampleMs: Long? = null

    companion object {
        /** Angles for one gravity sample; null in free fall (no usable "down"). */
        fun reading(gx: Double, gy: Double, gz: Double): Reading? {
            val g = sqrt(gx * gx + gy * gy + gz * gz)
            if (g < 3.0) return null
            val lean = Math.toDegrees(acos((abs(gz) / g).coerceIn(0.0, 1.0)))
            val roll = Math.toDegrees(atan2(abs(gx), abs(gy)))
            return Reading(lean, roll)
        }
    }

    /** Does this reading meet the posture right now (no waiting)? [relax] adds
     *  the hysteresis margin, used while already active. */
    fun matches(r: Reading, relax: Boolean = false): Boolean {
        val h = if (relax) config.hysteresisDeg else 0.0
        val leanOk = r.leanDeg >= config.minLeanDeg - h
        val rollOk = !config.landscapeOnly || r.rollDeg >= 45.0 - h
        return leanOk && rollOk
    }

    /** Feed one sample; returns whether the posture is active. */
    fun onSample(gx: Double, gy: Double, gz: Double, nowMs: Long): Boolean {
        // a hole in the data is not evidence either way: start the timers over.
        // (Every sample counts as data here, including free-fall ones.)
        val last = lastSampleMs
        lastSampleMs = nowMs
        if (last != null && nowMs - last > config.maxGapMs) {
            goodSince = null
            badSince = null
        }
        val r = reading(gx, gy, gz) ?: return active // free fall: ignore
        if (matches(r, relax = active)) {
            badSince = null
            if (!active) {
                val since = goodSince ?: nowMs.also { goodSince = it }
                if (nowMs - since >= config.enterDwellMs) active = true
            }
        } else {
            goodSince = null
            if (active) {
                val since = badSince ?: nowMs.also { badSince = it }
                if (nowMs - since >= config.exitDwellMs) {
                    active = false
                    badSince = null
                }
            }
        }
        return active
    }

    fun reset() {
        active = false
        goodSince = null
        badSince = null
        lastSampleMs = null
    }
}
