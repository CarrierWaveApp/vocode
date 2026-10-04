import XCTest
@testable import DMRMonitor

final class MicConditionerTests: XCTestCase {
    // MARK: Internal

    func testSpeechLevelInputPassesAtUnity() {
        var conditioner = MicConditioner()
        var lastPeak: Float = 0
        for var frame in sine(300, amplitude: 0.1, frames: 20) {
            conditioner.process(&frame)
            lastPeak = peak(frame)
        }
        // No makeup gain; only a little high-pass loss at 300 Hz
        XCTAssertGreaterThan(lastPeak, 0.08)
        XCTAssertLessThan(lastPeak, 0.11)
    }

    func testLoudInputIsHeldAtCeilingNotWrapped() {
        var conditioner = MicConditioner()
        for (index, var frame) in sine(300, amplitude: 0.95, frames: 50).enumerated() {
            conditioner.process(&frame)
            XCTAssertLessThanOrEqual(peak(frame), 0.96, "clamp must hold")
            if index > 0 {
                XCTAssertLessThanOrEqual(peak(frame), 0.52, "limiter must hold -6 dBFS after the first frame")
                XCTAssertGreaterThan(peak(frame), 0.45, "limiter must not squash below the ceiling")
            }
        }
    }

    func testLimiterGainDoesNotJumpBetweenSamples() {
        var conditioner = MicConditioner()
        // Steady loud tone: once settled, consecutive samples should differ
        // by no more than the tone's own slope (sample-rate gain changes
        // were the earlier "kick drum" distortion)
        var frames = sine(300, amplitude: 0.95, frames: 10)
        for index in frames.indices {
            conditioner.process(&frames[index])
        }
        let maxSlope = 0.52 * 2 * Float.pi * 300 / 8_000 * 1.2
        let settled = frames[5...].flatMap { $0 }
        for pair in zip(settled, settled.dropFirst()) {
            let step = abs(Float(pair.1) - Float(pair.0)) / 32_767
            XCTAssertLessThanOrEqual(step, maxSlope)
        }
    }

    func testLimiterReleasesAfterLoudPassage() {
        var conditioner = MicConditioner()
        for var frame in sine(300, amplitude: 0.95, frames: 10) {
            conditioner.process(&frame)
        }
        var lastPeak: Float = 0
        for var frame in sine(300, amplitude: 0.1, frames: 40) {
            conditioner.process(&frame)
            lastPeak = peak(frame)
        }
        XCTAssertGreaterThan(lastPeak, 0.08, "gain must recover toward unity between words")
    }

    func testRumbleIsAttenuatedMoreThanSpeech() {
        /// Early frames show the raw high-pass response before anything
        /// else settles
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
