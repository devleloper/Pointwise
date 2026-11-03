import Foundation
import Testing
@testable import PointwiseCore

struct ScrollEventKindTests {
    @Test func phasesMeanGestureDevice() {
        #expect(ScrollEventKind(isContinuous: true, scrollPhase: 1, momentumPhase: 0) == .gesture)
        #expect(ScrollEventKind(isContinuous: true, scrollPhase: 0, momentumPhase: 2) == .gesture)
        // A phase wins even if the event claims to be discrete.
        #expect(ScrollEventKind(isContinuous: false, scrollPhase: 4, momentumPhase: 0) == .gesture)
    }

    @Test func wheelsWithoutPhases() {
        #expect(ScrollEventKind(isContinuous: true, scrollPhase: 0, momentumPhase: 0) == .preciseWheel)
        #expect(ScrollEventKind(isContinuous: false, scrollPhase: 0, momentumPhase: 0) == .notchedWheel)
    }
}

struct WheelSpeedEstimatorTests {
    @Test func firstNotchIsAtRest() {
        var estimator = WheelSpeedEstimator()
        #expect(estimator.registerNotch(direction: 1, at: 10) == 0)
    }

    @Test func steadySpinConvergesToItsRate() {
        var estimator = WheelSpeedEstimator()
        var speed = 0.0
        for index in 0..<20 {
            speed = estimator.registerNotch(direction: -1, at: Double(index) * 0.05)
        }
        #expect(abs(speed - 20) < 0.001)
    }

    @Test func pauseOrReversalResets() {
        var estimator = WheelSpeedEstimator()
        estimator.registerNotch(direction: 1, at: 0)
        #expect(estimator.registerNotch(direction: 1, at: 0.05) > 0)
        #expect(estimator.registerNotch(direction: -1, at: 0.1) == 0)
        #expect(estimator.registerNotch(direction: -1, at: 0.1 + WheelSpeedEstimator.resetInterval) == 0)
    }

    @Test func bunchedNotchesDontInflateTheSpeed() {
        var estimator = WheelSpeedEstimator()
        estimator.registerNotch(direction: 1, at: 1)
        #expect(abs(estimator.registerNotch(direction: 1, at: 1.1) - 10) < 1e-9)
        // A second notch in the same instant and one a millisecond later are bunched reports.
        #expect(abs(estimator.registerNotch(direction: 1, at: 1.1) - 10) < 1e-9)
        #expect(abs(estimator.registerNotch(direction: 1, at: 1.101) - 10) < 1e-9)
        // Measured from the last accepted notch: 0.2 s, i.e. 5 per second, smoothed with 10.
        #expect(abs(estimator.registerNotch(direction: 1, at: 1.3) - 7.5) < 1e-9)
    }
}

struct ScrollAccelerationCurveTests {
    @Test func noAccelerationIsFlat() {
        let curve = ScrollAccelerationCurve(acceleration: 0)
        for speed in stride(from: 0.0, through: 60, by: 5) {
            #expect(curve.multiplier(notchesPerSecond: speed) == 1)
        }
    }

    @Test func slowScrollingIsNeverAccelerated() {
        let curve = ScrollAccelerationCurve(acceleration: 1)
        #expect(curve.multiplier(notchesPerSecond: ScrollAccelerationCurve.threshold) == 1)
        #expect(curve.multiplier(notchesPerSecond: 1) == 1)
    }

    @Test func monotonicAndBounded() {
        for acceleration in [0.25, 0.5, 1] {
            let curve = ScrollAccelerationCurve(acceleration: acceleration)
            var previous = 0.0
            for speed in stride(from: 0.0, through: 200, by: 0.5) {
                let value = curve.multiplier(notchesPerSecond: speed)
                #expect(value >= previous)
                #expect(value <= curve.maximumMultiplier)
                previous = value
            }
        }
    }

    @Test func fullAccelerationAtReference() {
        let curve = ScrollAccelerationCurve(acceleration: 1)
        #expect(abs(curve.multiplier(notchesPerSecond: ScrollAccelerationCurve.reference) - (1 + ScrollAccelerationCurve.maximumBoost)) < 1e-9)
    }

    @Test func invalidInputIsSafe() {
        let curve = ScrollAccelerationCurve(acceleration: .nan)
        #expect(curve.acceleration == 0)
        #expect(ScrollAccelerationCurve(acceleration: 1).multiplier(notchesPerSecond: .infinity) == 1)
        #expect(ScrollAccelerationCurve(acceleration: 5).acceleration == 1)
    }
}

struct GlideAnimatorTests {
    @Test func easingStartsFastAndEndsAtOne() {
        #expect(GlideAnimator.progress(elapsed: 0, duration: 0.3, exponent: 3) == 0)
        #expect(GlideAnimator.progress(elapsed: 0.3, duration: 0.3, exponent: 3) == 1)
        #expect(GlideAnimator.progress(elapsed: 1, duration: 0.3, exponent: 3) == 1)
        // Front-loaded: more than half the distance in the first third.
        #expect(GlideAnimator.progress(elapsed: 0.1, duration: 0.3, exponent: 3) > 0.5)
        #expect(GlideAnimator.progress(elapsed: 0, duration: 0, exponent: 3) == 1)
    }

    @Test func deliversExactDistanceRegardlessOfFrameTiming() {
        for frame in [1.0 / 30, 1.0 / 60, 1.0 / 120, 0.013] {
            var animator = GlideAnimator()
            animator.add(distance: 120, at: 0, duration: 0.3, exponent: 3)
            animator.add(distance: 80, at: 0.05, duration: 0.3, exponent: 3)
            var total = 0.0
            var time = 0.0
            while animator.isActive {
                time += frame
                total += animator.advance(to: time)
            }
            #expect(abs(total - 200) < 1e-9)
        }
    }

    @Test func reversalCancelsRemainingGlide() {
        var animator = GlideAnimator()
        animator.add(distance: 100, at: 0, duration: 0.5, exponent: 2)
        _ = animator.advance(to: 0.1)
        animator.add(distance: -40, at: 0.1, duration: 0.5, exponent: 2)
        #expect(animator.remainingDistance == -40)
        var total = 0.0
        var time = 0.1
        while animator.isActive {
            time += 0.01
            total += animator.advance(to: time)
        }
        #expect(abs(total + 40) < 1e-9)
    }

    @Test func segmentLimitKeepsDistance() {
        var animator = GlideAnimator()
        for index in 0..<(GlideAnimator.maximumSegments * 2) {
            animator.add(distance: 10, at: Double(index) * 0.001, duration: 1, exponent: 2)
        }
        #expect(abs(animator.remainingDistance - Double(GlideAnimator.maximumSegments * 2 * 10)) < 1e-9)
    }

    @Test func ignoresZeroAndInvalidDistances() {
        var animator = GlideAnimator()
        animator.add(distance: 0, at: 0, duration: 0.2, exponent: 2)
        animator.add(distance: .nan, at: 0, duration: 0.2, exponent: 2)
        #expect(!animator.isActive)
    }
}

struct FractionAccumulatorTests {
    @Test func keepsFractions() {
        var accumulator = FractionAccumulator()
        #expect(accumulator.take(0.4) == 0)
        #expect(accumulator.take(0.4) == 0)
        #expect(accumulator.take(0.4) == 1)
        #expect(abs(accumulator.remainder - 0.2) < 1e-9)
        #expect(accumulator.take(-1.7) == -1)
        #expect(accumulator.flush() == 0)
    }

    @Test func flushRoundsRemainder() {
        var accumulator = FractionAccumulator()
        _ = accumulator.take(2.6)
        #expect(accumulator.flush() == 1)
        #expect(accumulator.remainder == 0)
    }
}

struct WheelScrollerTests {
    private func settings(smooth: Bool, acceleration: Double = 0, lines: Double = 4) -> ScrollSettings {
        var settings = ScrollSettings()
        settings.isSmoothScrollingEnabled = smooth
        settings.acceleration = acceleration
        settings.linesPerNotch = lines
        return settings
    }

    private func lines(_ delivery: WheelScroller.Delivery) -> WheelScroller.Output {
        if case .lines(let output) = delivery { output } else { .zero }
    }

    private func points(_ delivery: WheelScroller.Delivery) -> WheelScroller.Output {
        if case .points(let output) = delivery { output } else { .zero }
    }

    @Test func instantNotchRewritesWholeLines() {
        var scroller = WheelScroller(settings: settings(smooth: false))
        #expect(scroller.notch(on: .vertical, direction: 1, at: 0, leadTime: 0) == .lines(.init(vertical: 4)))
        #expect(scroller.notch(on: .horizontal, direction: -3, at: 1, leadTime: 0) == .lines(.init(horizontal: -4)))
        #expect(!scroller.isGliding)
    }

    @Test func fractionalLinesCarryOver() {
        var scroller = WheelScroller(settings: settings(smooth: false, lines: 1.5))
        let deliveries = (0..<4).map { scroller.notch(on: .vertical, direction: 1, at: Double($0), leadTime: 0) }
        #expect(deliveries.map { lines($0).vertical } == [1, 2, 1, 2])
    }

    @Test func reversingDropsTheOldFraction() {
        var scroller = WheelScroller(settings: settings(smooth: false, lines: 1.5))
        _ = scroller.notch(on: .vertical, direction: 1, at: 0, leadTime: 0)
        // Without the reset, the +0.5 left over would cancel half of this notch.
        #expect(lines(scroller.notch(on: .vertical, direction: -1, at: 1, leadTime: 0)).vertical == -1)
    }

    @Test func reversalFlipsOnlyItsAxis() {
        var configuration = settings(smooth: false)
        configuration.reverseVertical = true
        var scroller = WheelScroller(settings: configuration)
        #expect(scroller.notch(on: .vertical, direction: 1, at: 0, leadTime: 0) == .lines(.init(vertical: -4)))
        #expect(scroller.notch(on: .horizontal, direction: 1, at: 0, leadTime: 0) == .lines(.init(horizontal: 4)))
        #expect(scroller.reversalSign(for: .vertical) == -1)
        #expect(scroller.reversalSign(for: .horizontal) == 1)
    }

    @Test func glideDeliversWholeDistanceAndStartsImmediately() {
        var scroller = WheelScroller(settings: settings(smooth: true, lines: 3))
        let first = points(scroller.notch(on: .vertical, direction: -1, at: 5, leadTime: 1.0 / 120))
        #expect(first.vertical < 0)
        var total = first.vertical
        var time = 5.0
        while scroller.isGliding {
            time += 1.0 / 120
            total += scroller.frame(at: time).vertical
        }
        #expect(total == -30)
    }

    @Test func fastSpinTravelsFurtherWithAcceleration() {
        var flat = WheelScroller(settings: settings(smooth: false, acceleration: 0))
        var accelerated = WheelScroller(settings: settings(smooth: false, acceleration: 1))
        var flatTotal = 0
        var acceleratedTotal = 0
        for index in 0..<10 {
            let time = Double(index) * 0.03
            flatTotal += lines(flat.notch(on: .vertical, direction: 1, at: time, leadTime: 0)).vertical
            acceleratedTotal += lines(accelerated.notch(on: .vertical, direction: 1, at: time, leadTime: 0)).vertical
        }
        #expect(flatTotal == 40)
        #expect(acceleratedTotal > flatTotal * 3)
    }

    @Test func switchingModesStopsGlideAndClearsRemainders() {
        var scroller = WheelScroller(settings: settings(smooth: true))
        _ = scroller.notch(on: .vertical, direction: 1, at: 0, leadTime: 0)
        #expect(scroller.isGliding)
        scroller.update(settings: settings(smooth: false))
        #expect(!scroller.isGliding)
        #expect(scroller.notch(on: .vertical, direction: 1, at: 1, leadTime: 0) == .lines(.init(vertical: 4)))
    }
}
