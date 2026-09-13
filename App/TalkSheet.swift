import SwiftUI

// MARK: - TxDestination

/// TX destination for the talk UI: the linked node on AllStar, the
/// selected talkgroup on BrandMeister. D-STAR and hotspot links are
/// receive-only — the talk UI says so instead of dangling a dead PTT.
struct TxDestination {
    // MARK: Lifecycle

    init(_ settings: Settings) {
        switch settings.activeKind {
        case .allstar:
            let node = settings.aslTarget.trimmingCharacters(in: .whitespaces)
            title = "Node \(node)"
            tag = "Node \(node)"
            armed = true
            rxOnly = false
        case .brandmeister:
            title = settings.txTarget.map { $0.name.isEmpty ? "TG \($0.tg)" : $0.name }
            tag = settings.txTarget.map { "TG \($0.tg)" }
            armed = settings.txTarget?.listen == .live
            rxOnly = false
        case .hotspot:
            title = settings.txTarget.map { $0.name.isEmpty ? "TG \($0.tg)" : $0.name }
            tag = settings.txTarget.map { "TG \($0.tg)" }
            armed = false
            rxOnly = true
        case .dstar:
            title = settings.connectedSummary
            tag = nil
            armed = false
            rxOnly = true
        }
    }

    // MARK: Internal

    let title: String?
    let tag: String?
    let armed: Bool
    let rxOnly: Bool

    /// Status line under the title, shared by the bar and the sheet
    func status(transmitting: Bool) -> String {
        if rxOnly {
            return "Receive only"
        }
        guard let tag else {
            return "Choose a talkgroup to talk"
        }
        if transmitting {
            return "Transmitting · \(tag)"
        }
        return armed ? "Ready · \(tag)" : "Target muted · \(tag)"
    }
}

// MARK: - PTTLabel

enum PTTLabel {
    static func text(transmitting: Bool, toggleMode: Bool) -> String {
        if transmitting {
            return toggleMode ? "Tap to stop" : "On air"
        }
        return toggleMode ? "Tap to talk" : "Hold to talk"
    }
}

// MARK: - TalkSheet

/// Expanded push-to-talk view: a large PTT button with the same
/// hold/toggle behavior as the compact talk bar
struct TalkSheet: View {
    // MARK: Internal

    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings

    var body: some View {
        let dest = TxDestination(settings)
        VStack(spacing: 8) {
            Text(dest.title ?? "No talk target")
                .font(CW.sans(18, .semibold))
                .foregroundStyle(dest.title != nil ? CW.white : CW.dim)
            Text(dest.status(transmitting: model.transmitting))
                .font(CW.sans(12))
                .foregroundStyle(model.transmitting ? CW.red : CW.dim)
            Spacer()
            pttButton(dest)
            Spacer()
            footerLine
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CW.bg)
        // No invisible hot mic: dismissing the sheet ends TX
        .onDisappear { model.endTransmit() }
    }

    // MARK: Private

    private var timeoutLabel: String {
        let secs = settings.txTimeoutSecs
        return secs < 60 ? "\(secs) sec" : "\(secs / 60) min"
    }

    @ViewBuilder private var footerLine: some View {
        if model.transmitting, let started = model.txBursts.first?.started {
            Text(started, style: .timer)
                .font(CW.mono(15, medium: true))
                .foregroundStyle(CW.white)
        } else if settings.txTimeoutSecs > 0 {
            Text("Timeout \(timeoutLabel)")
                .font(CW.sans(12))
                .foregroundStyle(CW.dim)
        } else {
            Text("Timeout off")
                .font(CW.sans(12))
                .foregroundStyle(CW.dim)
        }
    }

    @ViewBuilder
    private func pttButton(_ dest: TxDestination) -> some View {
        let transmitting = model.transmitting
        let circle = ZStack {
            Circle()
                .fill(transmitting ? CW.red : (dest.armed ? CW.blue : CW.raised))
            VStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 46))
                    .symbolEffect(.pulse, isActive: transmitting)
                Text(PTTLabel.text(transmitting: transmitting, toggleMode: settings.pttToggle))
                    .font(CW.sans(16, .semibold))
            }
            .foregroundStyle(transmitting ? CW.white : (dest.armed ? CW.bg : CW.text))
        }
        .frame(width: 190, height: 190)
        .overlay(Circle().stroke(dest.armed || transmitting ? .clear : CW.border, lineWidth: 1))
        .opacity(dest.armed || transmitting ? 1 : 0.45)
        if settings.pttToggle {
            circle.onTapGesture {
                if model.transmitting {
                    model.endTransmit()
                } else if dest.armed {
                    model.beginTransmit(settings)
                }
            }
        } else {
            circle.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if dest.armed, !model.transmitting {
                            model.beginTransmit(settings)
                        }
                    }
                    .onEnded { _ in model.endTransmit() }
            )
        }
    }
}
