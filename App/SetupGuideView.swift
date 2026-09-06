import SwiftUI

/// First-run walkthrough: where DMR IDs and passwords come from, and what
/// goes in which Settings field. Pure static content.
struct SetupGuideView: View {
    var body: some View {
        Form {
            Section {
                Step(1, "Register at radioid.net with a copy of your amateur radio license. "
                    + "Registration is free; approval usually takes a day.")
                Step(2, "You'll be issued a 7-digit personal DMR ID. That's what goes in the DMR ID "
                    + "field here — one ID per operator, shared across all your radios and hotspots.")
                GuideLink("radioid.net", url: "https://radioid.net")
            } header: {
                SectionLabel("Get a DMR ID")
            }
            Section {
                Step(1, "Create an account at brandmeister.network. Registration asks for your "
                    + "callsign and DMR ID, so get the ID first.")
                Step(2, "Log in and open SelfCare, then turn on Hotspot Security and set a password.")
                Step(3, "That hotspot security password is what goes in the password field here — "
                    + "not your BrandMeister account login password.")
                GuideLink("brandmeister.network SelfCare", url: "https://brandmeister.network/?page=selfcare")
            } header: {
                SectionLabel("BrandMeister password")
            }
            Section {
                Step(1, "Protocol: Open Terminal. This is BrandMeister's sanctioned mode for apps "
                    + "without a radio, and the only mode that can transmit.")
                Step(2, "Master: automatic by default — Connect pings every BrandMeister master "
                    + "and uses the fastest. Tap the Master row to see latencies or pin one yourself.")
                Step(3, "Enter your 7-digit DMR ID (no suffix) and your hotspot security password.")
                Step(4, "Add talkgroups below, then tap Connect on the main screen. "
                    + "Tap a talkgroup's status to cycle live, muted, off.")
            } header: {
                SectionLabel("Configure the app")
            }
            Section {
                Step(1, "Homebrew is the MMDVM hotspot protocol on port 62031. BrandMeister rejects "
                    + "app-only clients here — that's what Open Terminal is for — but other networks allow it.")
                Step(2, "TGIF: make an account at tgif.network and use the password from its self-care page.")
                Step(3, "Homebrew needs your callsign plus a two-digit hotspot suffix. Any two digits "
                    + "work as long as no other hotspot on your DMR ID uses them; 01 is fine.")
                GuideLink("tgif.network", url: "https://tgif.network")
            } header: {
                SectionLabel("Homebrew mode (TGIF and others)")
            }
        }
        .cwList()
        .navigationTitle("Setup guide")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(CW.mono(13, medium: true))
                .foregroundStyle(CW.blue)
            Text(text)
                .font(CW.sans(14))
                .foregroundStyle(CW.text)
        }
        .padding(.vertical, 2)
    }
}

private struct GuideLink: View {
    let label: String
    let url: String

    init(_ label: String, url: String) {
        self.label = label
        self.url = url
    }

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square")
                Text(label)
            }
            .font(CW.mono(13))
            .foregroundStyle(CW.blue)
        }
    }
}
