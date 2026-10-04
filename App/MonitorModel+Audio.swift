import AVFoundation
import Foundation

/// Audio session mode switching around transmit
extension MonitorModel {
    /// RX runs under .playback so Bluetooth headphones get the A2DP route
    /// (full quality, reliable). The mic needs .playAndRecord, so flip to it
    /// only while keyed up; HFP is what carries a headset mic. TX uses
    /// .voiceChat — the voice-optimized input chain (AGC/EQ/AEC) — not
    /// .spokenAudio, which is a playback mode and leaves the mic raw.
    func setTransmitAudioSession(_ transmitting: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if transmitting {
                try session.setCategory(
                    .playAndRecord, mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetoothHFP]
                )
            } else {
                try session.setCategory(.playback, mode: .spokenAudio)
            }
            try session.setActive(true)
        } catch {
            appendLog("audio session switch failed", error: true)
        }
    }

    /// Foreground hook: iOS stops the playback engine while the app is
    /// suspended and doesn't always say so; this restarts it if needed
    func resumeAudio() {
        pipeline.resumeAudio()
    }

    /// Playback engine restarts after interruptions, route changes, and
    /// foregrounding report here so a failure is visible instead of silent
    func audioRestarted(_ reason: String, error: Error?) {
        if let error {
            audioError = "Audio stopped: \(reason)"
            appendLog("audio restart failed (\(reason)): \(error.localizedDescription)", error: true)
        } else {
            audioError = nil
            appendLog("audio resumed (\(reason))")
        }
    }

    /// What the network heard: play back the encoded->decoded copy of the
    /// last transmission
    func playLastTX() {
        playMonitor(txMonitor.audio)
    }

    /// The conditioned mic BEFORE the codec — bisects capture problems
    /// from codec problems
    func playLastMic() {
        playMonitor(txMonitor.micAudio)
    }

    private func playMonitor(_ audio: [Float]) {
        guard !transmitting, !audio.isEmpty else {
            return
        }
        let output = monitorOut ?? AudioOutput()
        monitorOut = output
        try? output.start()
        output.play(audio)
    }

    var hasLastTX: Bool {
        !txMonitor.audio.isEmpty
    }
}
