import SwiftUI

/// Settings block: play back the encoded->decoded copy of the last
/// transmission — exactly what the network heard
struct TxMonitorSection: View {
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        Section {
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
            Text("Hears your last TX after the AMBE encode/decode round trip — what other stations heard.")
                .font(CW.mono(11))
                .foregroundStyle(CW.dim)
        }
    }
}
