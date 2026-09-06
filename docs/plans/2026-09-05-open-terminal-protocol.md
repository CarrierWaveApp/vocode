# Open Terminal Protocol support

BrandMeister refuses homebrew-protocol logins from app-only clients (MSTNAK
after RPTC). Their sanctioned path for RF-less terminals is the Open DMR
Terminal Protocol, built on the Rewind protocol over UDP, port 54006.

References studied (scratchpad clones):
- abo4/pyspot_rx — working RX-only Python OTP client (primary blueprint)
- BrandMeister/go-brandmeister — official Go implementation of Rewind framing
- redfast00 blog — confirms audio arrives as 3x 9-byte FEC'd AMBE frames

## Protocol summary

Frame: `REWIND01` + type(2 LE) + flags(2 LE) + seq(4 LE) + len(2 LE) + payload.

Login: client sends KEEP_ALIVE (payload = dmrID(4 LE) + 0x21 service byte +
description); server replies CHALLENGE with 4-byte token; client sends
AUTHENTICATION = SHA256(token + password); server's next KEEP_ALIVE reply
means logged in. Password is the same SelfCare hotspot-security password.
DMR ID is the plain 7-digit ID, no suffix.

Subscribe: SUBSCRIPTION (0x0901), payload = UInt32 LE 7 (group) + tg(4 LE).
Voice: HEADER_WITH_FLC (0x0911, FLC has dst/src as 3-byte BE at offsets 3/6),
DMR_AUDIO_FRAME (0x0920, 27-byte payload = 3x 9-byte on-air AMBE frames),
TERMINATOR_WITH_FLC (0x0912). New call detected by header seq gap.
Keep-alive every 5 s, dead after 15 s without ack.

## Changes

1. `App/RewindClient.swift` (new) — OTP client mirroring HomebrewClient's
   shape (NWConnection UDP, LinkState, onState/onLog callbacks; plus
   onCallStart/onAudio/onCallEnd).
2. `App/DMRFrame.swift` — `VoiceBurst.ambeFrame(_:)`: 9-byte frame → 96-cell
   mbelib layout using the existing rW/rX/rY/rZ schedule.
3. `App/MonitorModel.swift` — protocol dispatch on connect, generalized
   openCall, `DecodePipeline.submitAmbe` for pre-extracted frames.
4. `App/Settings.swift` — `netMode` (openterminal|homebrew), `otpPort`
   (54006), `rewindConfig`, talkgroup parser tolerant of both
   `TS2_1=91;TS2_2=3100` and `91;3100` forms.
5. `App/ContentView.swift` — protocol picker; homebrew-only fields hidden in
   OTP mode; hide TS tag when slot is 0 (OTP has no timeslot).
6. README — document the two modes.
