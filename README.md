# DMR Monitor (iOS)

Receive-only DMR talkgroup monitor for iPhone. Decodes AMBE+2 voice with
mbelib, plays it, and keeps a last-heard list. Two network modes:

- **Open Terminal (default)** — BrandMeister's sanctioned protocol for
  RF-less terminals (Rewind framing, UDP port 54006). Same master
  hostnames, plain 7-digit DMR ID (no suffix), same SelfCare
  hotspot-security password. Talkgroups are subscribed directly; the
  options field accepts `91;3100` or the MMDVMHost `TS2_1=91` form.
- **Homebrew (hotspot)** — the MMDVM homebrew protocol, port 62031.
  BrandMeister NAKs app-only clients here (that's why Open Terminal
  exists); still useful for networks that allow it, e.g. TGIF.

Transmit works in Open Terminal mode: hold the talk button to key up the
selected TX talkgroup. Voice is encoded with OP25's software AMBE+2
encoder (GPL v3, vendored under `Packages/AMBE/Sources/CMBELib/encoder/`
with a custom `dmr_pack.cc` that emits mbelib's cell layout — the package
test proves encode→decode symmetry). No transmit on homebrew mode.

No App Store distribution intended.

## Layout

    App/                    SwiftUI app sources
    Packages/AMBE/          Swift package wrapping vendored mbelib (C)
    project.yml             XcodeGen spec

## Build

    brew install xcodegen
    xcodegen generate
    open DMRMonitor.xcodeproj

Set your team under Signing, build to a device. The simulator works for
network and decode but audio routing is flaky there.

## BrandMeister setup

1. SelfCare → enable Hotspot Security, set a password.
2. DMR ID: your 7-digit ID. Suffix: any two digits not used by another
   hotspot on your ID (01 is fine).
3. Options: static talkgroups in MMDVMHost format,
   `TS2_1=91;TS2_2=3100`. BM reads these from the RPTO packet the same
   way it reads Pi-Star's Options field. If BM ignores it on your
   master, add static TGs on the hotspot in SelfCare instead.
4. Master: `NNNN.master.brandmeister.network`, port 62031. 3101–3104
   are the US masters.

## Callsign notes

Settings → Callsign notes. Same file format and share-link handling as
PoLo (https://polo.ham2k.com/docs/polo-features/callsign-notes/): one
call per line, then the note; `#` and blank lines ignored; a leading
emoji is shown next to the callsign; basic markdown in the note.
Dropbox, Google Drive, Google Docs, Gist and iCloud Drive share links
are rewritten to direct downloads the same way PoLo does it.

Ham2K's Hams of Note is built in and on by default. Files are checked
in list order, first match wins, drag to reorder. Enabled files refresh
when older than a day on connect, or swipe to refresh now. Parsed
files are cached in Application Support so notes work offline.

Notes key off the callsign resolved from radioid.net, so a DMR ID that
isn't registered there gets no note.

## Map

The map toolbar button shows heard stations (filled pins) plus a live
BrandMeister network overlay (hollow pins) pulled from BM's last-heard
Socket.IO feed, joined per talkgroup room. The overlay follows your
subscribed talkgroups by default, or pick one in the map's filter menu;
it only runs while the map is on screen. Coordinates come from the QRZ
XML API (Settings → QRZ; a QRZ subscription is required for lat/lon),
falling back to grid-square centers, and are cached on disk. Pins fade
with age: heard stations linger an hour, overlay stations 15 minutes.

## What it does not do yet

- Dynamic TG subscription by kerchunk. That needs a valid LC header
  with BPTC(196,96) FEC and embedded LC, which is the bulk of a TX path.
- Private calls. Dropped on purpose.
- Reconnect. A failed link stays failed until you tap Connect.
- Jitter buffer. Bursts go straight to AVAudioPlayerNode. Fine on
  wifi, may stutter on bad cellular.
- DMR+ / TGIF / IPSC2. Homebrew protocol only, tested against BM
  semantics.

## Where the bits come from

`DMRFrame.swift` pulls three 72-bit AMBE frames out of the 264-bit
burst (frame 2 wraps the 48-bit sync/embedded field) and deinterleaves
with the rW/rX/rY/rZ schedule from DSD's `dmr_const.h`.
`ambe_shim.c` feeds each frame to `mbe_processAmbe3600x2450Frame`.

## Theme

Dark only, matching carrierwave.app: `#0e0f11` background, `#4a8cff`
accent, `#22c55e` for live status, Outfit for text and IBM Plex Mono
for callsigns, IDs and section labels. Everything lives in
`App/Theme.swift`. Fonts are bundled under `Resources/Fonts` (OFL,
licenses alongside).

## Licensing

mbelib is ISC-licensed (see `Packages/AMBE/Sources/CMBELib/COPYRIGHT.mbelib`).
Its README warns the vocoder may be covered by DVSI patents. You've
read that already.
