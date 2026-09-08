import Foundation
import AVFoundation

// Audio session mode switching around transmit
extension MonitorModel {
    // RX runs under .playback so Bluetooth headphones get the A2DP route
    // (full quality, reliable). The mic needs .playAndRecord, so flip to it
    // only while keyed up; HFP is what carries a headset mic.
    func setTransmitAudioSession(_ transmitting: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if transmitting {
                try session.setCategory(
                    .playAndRecord, mode: .spokenAudio,
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
}
