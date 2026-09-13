import SwiftUI

// MARK: - SetupGuideView

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
                Step(1, "Enter your callsign, 7-digit DMR ID (no suffix), and your hotspot "
                    + "security password in Settings.")
                Step(2, "Tap the title on the main screen to open destinations. The built-in "
                    + "BrandMeister destination connects to the nearest master automatically "
                    + "via Open Terminal — BrandMeister's sanctioned mode for apps without a "
                    + "radio, and the only DMR mode that can transmit.")
                Step(3, "Edit the destination to add talkgroups, then tap it to connect. "
                    + "Tap a talkgroup's speaker for live, muted, or off.")
            } header: {
                SectionLabel("Configure the app")
            }
            Section {
                Step(1, "A hotspot destination speaks the MMDVM Homebrew protocol on port 62031. "
                    + "BrandMeister rejects app-only clients here — that's what the BrandMeister "
                    + "destination is for — but other networks allow it.")
                Step(2, "TGIF: make an account at tgif.network and use the password from its self-care page.")
                Step(3, "Homebrew needs your callsign plus a two-digit hotspot suffix in Settings. "
                    + "Any two digits work as long as no other hotspot on your DMR ID uses them; 01 is fine.")
                GuideLink("tgif.network", url: "https://tgif.network")
            } header: {
                SectionLabel("Hotspot destinations (TGIF and others)")
            }
            Section {
                Step(1, "Create an account at allstarlink.org with a copy of your license, "
                    + "then open the portal.")
                Step(2, "Add a server (Portal → Servers), then request a node number under it "
                    + "(Portal → Node Requests). The app acts as its own node, so give it a node "
                    + "of its own — don't reuse a hardware node's number.")
                Step(3, "The node number and its password from the node settings page go in "
                    + "Settings, along with your callsign.")
                Step(4, "Add an AllStar destination, pick a node to link to, and tap it to "
                    + "connect. The first connect after setup can be refused while AllStarLink's "
                    + "DNS catches up — wait a minute or two and try again.")
                GuideLink("allstarlink.org", url: "https://www.allstarlink.org")
            } header: {
                SectionLabel("AllStar destinations")
            }
        }
        .cwList()
        .navigationTitle("Setup guide")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Step

private struct Step: View {
    // MARK: Lifecycle

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    // MARK: Internal

    let number: Int
    let text: String

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

// MARK: - GuideLink

private struct GuideLink: View {
    // MARK: Lifecycle

    init(_ label: String, url: String) {
        self.label = label
        self.url = url
    }

    // MARK: Internal

    let label: String
    let url: String

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
