# Destination model + de-gimmick pass

Approved 2026-09-13. Fixes the multi-system UX (protocol picker buried in
Settings) and the gimmicky UI (terminal cosplay, no Dynamic Type).

## Architecture: saved destinations over working keys

The existing `@AppStorage` keys (`netMode`, `host`, `otpPort`, `port`,
`autoMaster`, `dstarHost`, `dstarModule`, `aslTarget`, `talkgroupsJSON`,
`txTargetTG`) stay as the **working state** — every config builder, picker,
and client keeps reading them unchanged. A new saved-destinations layer sits
on top, like a radio's memory channels over its VFO:

- `Destination` (Codable): `id`, `kind` (brandmeister/hotspot/dstar/allstar),
  `name`, `host`, `port`, `otpPort`, `autoMaster`, `module`, `node`,
  `talkgroups`, `txTargetTG`.
- `Settings.destinations` (`destinationsJSON`) + `activeDestinationID`.
- `activate(_:)`: snapshot working keys back into the currently active
  destination, then load the new one's fields into the working keys and set
  `netMode` from its kind.
- Migration in `Settings.init`: when `destinationsJSON` is empty, build one
  destination per configured system from the current keys; active = the one
  matching `netMode`.

## UI changes

- **Switcher**: nav-bar principal button (dot + destination name) opens
  `DestinationSwitcherView` sheet: status row + connect/disconnect + log
  link, destination list (tap = activate + reconnect), add menu (4 kinds),
  edit/delete. Replaces the hidden `connExpanded` toggle.
- **DestinationEditView**: per-kind fields; reuses the three pickers, which
  now take explicit bindings instead of writing `Settings` keys. DMR
  destinations edit their talkgroup list here.
- **SettingsView**: loses the Protocol picker, Master section, morphing
  StationSection, and Talkgroups editor. Gains static identity sections
  (Callsign+DMR / AllStar credentials). Keeps guide, data, QRZ, buddy,
  transmit, behavior, acknowledgements.
- **ContentView**: Talkgroups section renders only for DMR kinds and gains
  an Edit link; `TxDestination` becomes kind-aware (D-Star and hotspot are
  RX-only and say so instead of "SELECT IN TALKGROUPS").
- `NetsSection`/`NetScheduler`/`MonitorModel+History` keep their semantics
  via `Settings.kind` helpers.

## De-gimmick pass

- `CW.sans`/`CW.mono` gain `relativeTo:` text styles → Dynamic Type works
  app-wide from one place.
- `SectionLabel` drops the `// ` prefix and mono font.
- `TGRow`: tap-to-cycle button becomes a Menu (Live/Muted/Off); instruction
  footer deleted; 44pt targets.
- Talkgroup header count dots become icon+count (not color-only).
- All-caps mono microcopy (`TX TARGET ·`, `SELECT IN TALKGROUPS`,
  `TX TIMEOUT 2 MIN`) becomes sentence case sans; mono stays for data
  (callsigns, TGs, timestamps, latency, log).
- Footers switch from mono 11 to sans 12.

Dark-only stays — deliberate identity, defensible for a shack app.

## Verification

`xcodegen` → build via xc skill → swiftformat → swiftlint → existing tests
plus new `DestinationTests` (kind mapping, migration, activate round-trip).
