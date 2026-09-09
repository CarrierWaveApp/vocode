import XCTest
@testable import DMRMonitor

final class MicConditionerTests: XCTestCase {
    private func sine(_ frequency: Float, amplitude: Float, frames: Int) -> [[Int16]] {
        (0..<frames).map { frame in
            (0..<160).map { index in
                let sampleIndex = Float(frame * 160 + index)
                let value = amplitude * sin(2 * .pi * frequency * sampleIndex / 8000)
                return Int16(max(-32767, min(32767, value * 32767)))
            }
        }
    }

    private func peak(_ frame: [Int16]) -> Float {
        Float(frame.map { abs(Int32($0)) }.max() ?? 0) / 32767
    }

    func testQuietSpeechIsBoostedTowardTarget() {
        var conditioner = MicConditioner()
        var lastPeak: Float = 0
        // 4 seconds of a quiet 300 Hz tone at -30 dBFS
        for var frame in sine(300, amplitude: 0.03, frames: 200) {
            conditioner.process(&frame)
            lastPeak = peak(frame)
        }
        // -30 dBFS in, max makeup gain 8x -> ~0.24 out; the cap is
        // deliberate since .voiceChat's system AGC runs ahead of us
        XCTAssertGreaterThan(lastPeak, 0.2, "AGC should approach the target level")
        XCTAssertLessThanOrEqual(lastPeak, 0.98)
    }

    func testLoudInputIsLimitedNotWrapped() {
        var conditioner = MicConditioner()
        for var frame in sine(300, amplitude: 0.95, frames: 50) {
            conditioner.process(&frame)
            XCTAssertLessThanOrEqual(peak(frame), 0.99, "limiter must clamp")
        }
    }

    func testRumbleIsAttenuatedMoreThanSpeech() {
        // Measure the first frames only: with isolated tones the AGC
        // eventually re-boosts whatever the filter removed, but early
        // frames show the raw high-pass response
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
        for _ in 0..<100 {
            var copy = frame
            conditioner.process(&copy)
            frame = [Int16](repeating: 12, count: 160)
            XCTAssertLessThan(peak(copy), 0.05, "near-silence must stay near-silent")
        }
    }
}
