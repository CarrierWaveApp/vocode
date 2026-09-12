import XCTest
@testable import DMRMonitor

final class MicConditionerTests: XCTestCase {
    // MARK: Internal

    func testFixedMakeupGainApplies() {
        var conditioner = MicConditioner()
        var lastPeak: Float = 0
        for var frame in sine(300, amplitude: 0.1, frames: 20) {
            conditioner.process(&frame)
            lastPeak = peak(frame)
        }
        // 2x fixed gain, minus a little high-pass loss at 300 Hz
        XCTAssertGreaterThan(lastPeak, 0.15)
        XCTAssertLessThan(lastPeak, 0.25)
    }

    func testLoudInputIsLimitedNotWrapped() {
        var conditioner = MicConditioner()
        for var frame in sine(300, amplitude: 0.95, frames: 50) {
            conditioner.process(&frame)
            XCTAssertLessThanOrEqual(peak(frame), 0.99, "limiter must clamp")
        }
    }

    func testRumbleIsAttenuatedMoreThanSpeech() {
        /// Measure the first frames only: with isolated tones the AGC
        /// eventually re-boosts whatever the filter removed, but early
        /// frames show the raw high-pass response
        func residual(_ frequency: Float) -> Float {
            var conditioner = MicConditioner()
            var total: Float = 0
            for var frame in sine(frequency, amplitude: 0.3, frames: 2) {
                conditioner.process(&frame)
                total += peak(frame)
            }
            return total
        }
        XCTAssertLessThan(residual(30), residual(300) * 0.6,
                          "30 Hz rumble should be clearly attenuated vs 300 Hz speech")
    }

    func testSilenceIsNotAmplifiedIntoHiss() {
        var conditioner = MicConditioner()
        var frame = [Int16](repeating: 12, count: 160)
        for _ in 0 ..< 100 {
            var copy = frame
            conditioner.process(&copy)
            frame = [Int16](repeating: 12, count: 160)
            XCTAssertLessThan(peak(copy), 0.05, "near-silence must stay near-silent")
        }
    }

    // MARK: Private

    private func sine(_ frequency: Float, amplitude: Float, frames: Int) -> [[Int16]] {
        (0 ..< frames).map { frame in
            (0 ..< 160).map { index in
                let sampleIndex = Float(frame * 160 + index)
                let value = amplitude * sin(2 * .pi * frequency * sampleIndex / 8_000)
                return Int16(max(-32_767, min(32_767, value * 32_767)))
            }
        }
    }

    private func peak(_ frame: [Int16]) -> Float {
        Float(frame.map { abs(Int32($0)) }.max() ?? 0) / 32_767
    }
}
