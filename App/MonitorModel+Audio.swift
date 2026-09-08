import Foundation
import AVFoundation

// Audio session mode switching around transmit
extension MonitorModel {
    // RX runs under .playback so Bluetooth headphones get the A2DP route
    // (full quality, reliable). The mic needs .playAndRecord, so flip to it
    // only while keyed up; HFP is what carries a headset mic. TX uses
    // .voiceChat — the voice-optimized input chain (AGC/EQ/AEC) — not
    // .spokenAudio, which is a playback mode and leaves the mic raw.
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

    // What the network heard: play back the encoded->decoded copy of the
    // last transmission
    func playLastTX() {
        guard !transmitting else { return }
        let audio = txMonitor.audio
        guard !audio.isEmpty else { return }
        let output = monitorOut ?? AudioOutput()
        monitorOut = output
        try? output.start()
        output.play(audio)
    }

    var hasLastTX: Bool { !txMonitor.audio.isEmpty }
}
