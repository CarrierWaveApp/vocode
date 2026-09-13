import SwiftUI

/// Settings block: PTT behavior plus playback of the encoded->decoded
/// copy of the last transmission — exactly what the network heard
struct TxMonitorSection: View {
    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings

    var body: some View {
        Section {
            Picker("PTT style", selection: settings.$pttToggle) {
                Text("Hold to talk").tag(false)
                Text("Tap to toggle").tag(true)
            }
            Picker("TX timeout", selection: settings.$txTimeoutSecs) {
                Text("30 sec").tag(30)
                Text("1 min").tag(60)
                Text("2 min").tag(120)
                Text("3 min").tag(180)
                Text("5 min").tag(300)
                Text("Off").tag(0)
            }
            Button("Play last transmission") {
                model.playLastTX()
            }
            .disabled(!model.hasLastTX || model.transmitting)
            Button("Play mic (before codec)") {
                model.playLastMic()
            }
            .disabled(!model.hasLastTX || model.transmitting)
        } header: {
            SectionLabel("Transmit")
        } footer: {
            FooterNote("Toggle keys up on one tap and stops on the next. The timeout "
                + "ends any transmission automatically. Playback hears your last "
                + "TX after the AMBE encode/decode round trip — what other "
                + "stations heard.")
        }
    }
}
