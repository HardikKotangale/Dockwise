package com.ytchannel.standbypro

import kotlin.math.cos
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PostureLogicTest {
    private val g = 9.81

    // gravity for a phone leaning [leanDeg] back from upright-landscape
    private fun landscape(leanFromFlatDeg: Double): Triple<Double, Double, Double> {
        val a = Math.toRadians(leanFromFlatDeg)
        return Triple(g * sin(a), 0.0, g * cos(a))
    }

    // feed [seconds] of samples at 5 Hz, return the final answer
    private fun hold(l: PostureLogic, s: Triple<Double, Double, Double>, seconds: Double, startMs: Long): Pair<Boolean, Long> {
        var t = startMs
        var out = l.active
        val end = startMs + (seconds * 1000).toLong()
        while (t <= end) {
            out = l.onSample(s.first, s.second, s.third, t)
            t += 200
        }
        return out to t
    }

    @Test fun flatIsNotPropped() {
        val r = PostureLogic.reading(0.0, 0.0, g)!!
        assertEquals(0.0, r.leanDeg, 0.01)
        assertFalse(PostureLogic().matches(r))
    }

    @Test fun uprightLandscapeIsPropped() {
        val r = PostureLogic.reading(g, 0.0, 0.0)!!
        assertEquals(90.0, r.leanDeg, 0.01)
        assertEquals(90.0, r.rollDeg, 0.01)
        assertTrue(PostureLogic().matches(r))
    }

    @Test fun leanAngleIsMeasuredFromFlat() {
        val (x, y, z) = landscape(60.0)
        assertEquals(60.0, PostureLogic.reading(x, y, z)!!.leanDeg, 0.01)
    }

    @Test fun portraitDoesNotMatchWhenLandscapeOnly() {
        val r = PostureLogic.reading(0.0, g, 0.0)!!
        assertEquals(0.0, r.rollDeg, 0.01)
        assertFalse(PostureLogic(PostureLogic.Config(landscapeOnly = true)).matches(r))
        assertTrue(PostureLogic(PostureLogic.Config(landscapeOnly = false)).matches(r))
    }

    @Test fun lean39DoesNotMatchButLean41Does() {
        val l = PostureLogic(PostureLogic.Config(minLeanDeg = 40.0))
        val (x1, y1, z1) = landscape(39.0)
        val (x2, y2, z2) = landscape(41.0)
        assertFalse(l.matches(PostureLogic.reading(x1, y1, z1)!!))
        assertTrue(l.matches(PostureLogic.reading(x2, y2, z2)!!))
    }

    @Test fun startsOnlyAfterTheDwell() {
        val l = PostureLogic()
        val s = landscape(70.0)
        assertFalse(hold(l, s, 1.2, 0).first) // 1.2 s < 1.5 s
        assertTrue(hold(PostureLogic(), s, 1.8, 0).first)
    }

    @Test fun aBriefBumpNeverStartsIt() {
        val l = PostureLogic()
        var (_, t) = hold(l, landscape(70.0), 1.0, 0) // propped for 1 s...
        val flat = Triple(0.0, 0.0, g)
        t = hold(l, flat, 0.6, t).second // ...then put flat: timer resets
        assertFalse(hold(l, landscape(70.0), 1.0, t).first) // again only 1 s
    }

    @Test fun staysActiveThroughAShortWobbleThenStopsAfterTheExitDwell() {
        val l = PostureLogic()
        var (active, t) = hold(l, landscape(70.0), 2.0, 0)
        assertTrue(active)
        val flat = Triple(0.0, 0.0, g)
        val wobble = hold(l, flat, 2.0, t) // lost for 2 s < 4 s
        assertTrue(wobble.first)
        val gone = hold(l, flat, 4.5, wobble.second) // lost > 4 s in total
        assertFalse(gone.first)
    }

    @Test fun hysteresisKeepsItActiveJustBelowTheStartAngle() {
        val l = PostureLogic(PostureLogic.Config(minLeanDeg = 40.0))
        var (active, t) = hold(l, landscape(60.0), 2.0, 0)
        assertTrue(active)
        // 35 deg is below 40 but inside the 10 deg margin: still counts
        assertTrue(hold(l, landscape(35.0), 6.0, t).first)
    }

    @Test fun freeFallSamplesAreIgnored() {
        assertNull(PostureLogic.reading(0.1, 0.1, 0.1))
        val l = PostureLogic()
        val (active, t) = hold(l, landscape(70.0), 2.0, 0)
        assertTrue(active)
        // a moment of weightlessness (phone dropped) must not stop it
        assertTrue(l.onSample(0.1, 0.1, 0.1, t + 10_000))
    }

    @Test fun resetClearsEverything() {
        val l = PostureLogic()
        assertTrue(hold(l, landscape(70.0), 2.0, 0).first)
        l.reset()
        assertFalse(l.active)
        assertNotNull(PostureLogic.reading(g, 0.0, 0.0))
    }

    // ---- Regression tests replaying the TLC counterexamples in spec/ ----

    // spec/results/PostureLogic_gaps.txt: one good sample, then NO samples for
    // a while, then another good sample. The old code compared the two
    // timestamps, decided "held for 1.5 s" and became active, although the
    // posture was never observed during the gap.
    @Test fun aHoleInTheDataIsNotEvidenceThatThePostureWasHeld() {
        val l = PostureLogic()
        val (x, y, z) = landscape(70.0)
        assertFalse(l.onSample(x, y, z, 0))
        assertFalse(l.onSample(x, y, z, 2000)) // 2 s later, nothing in between
        // and it still starts normally once the data is continuous again
        assertTrue(hold(l, landscape(70.0), 2.0, 2200).first)
    }

    // spec/results/PostureLogic_gaps_exit.txt: the same flaw on the exit side:
    // two "lost" samples with a hole between them turned an active posture off.
    @Test fun aHoleInTheDataIsNotEvidenceThatThePostureWasLost() {
        val l = PostureLogic()
        val (active, t) = hold(l, landscape(70.0), 2.0, 0)
        assertTrue(active)
        val flat = Triple(0.0, 0.0, g)
        assertTrue(l.onSample(flat.first, flat.second, flat.third, t)) // first "lost" sample
        // 5 s of silence, then another "lost" sample
        assertTrue(l.onSample(flat.first, flat.second, flat.third, t + 5000))
    }

    // the gap rule must not break ordinary sampling: a missed sample or two
    @Test fun aSingleMissedSampleIsTolerated() {
        val l = PostureLogic()
        val (x, y, z) = landscape(70.0)
        var t = 0L
        var out = false
        while (t <= 2000) {
            if (t != 600L) out = l.onSample(x, y, z, t) // one sample lost at 600 ms
            t += 200
        }
        assertTrue(out)
    }

    // a free-fall sample is still a sample: it proves the sensor is alive
    @Test fun freeFallSamplesCountAsDataForTheGapRule() {
        val l = PostureLogic()
        val (x, y, z) = landscape(70.0)
        var t = 0L
        var out = false
        while (t <= 2000) {
            out = if (t in 600..800) l.onSample(0.1, 0.1, 0.1, t) else l.onSample(x, y, z, t)
            t += 200
        }
        assertTrue(out)
    }
}
