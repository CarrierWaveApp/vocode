# DMRMonitor: Station Map (dmrmap.app-style)

## Context

Users want a live map like https://dmrmap.app/ — active/recent DMR callers plotted on a world map. Agreed scope: plot **both** stations the app itself hears (existing `heard` list) and a **Brandmeister network overlay** from BM's last-heard Socket.IO stream filtered by talkgroup; coordinates from the **QRZ XML API** (user has a subscription; credentials in Settings); entry point is a **map toolbar button** pushing a full-screen map. No user location (keeps `NSLocation*` keys out of Info.plist). Copy this plan to `docs/plans/2026-09-08-station-map.md` at implementation start.

Key facts: `DMRMonitor.xcodeproj` is generated — run `xcodegen generate` after adding files. Quality gate: warning-free `xc build`, `xc lint` ≤ 161-violation baseline (no swiftformat). Deploy: `xc deploy` to theseus. iOS 17 target, zero third-party deps (keep it that way — hand-roll a minimal Engine.IO v4 client).

## New files (all in App/, added via xcodegen)

### 1. `GeoPoint.swift` (~60 lines)
- `struct GeoPoint: Equatable, Hashable, Codable { let lat, lon: Double }` — keeps MapKit out of MonitorModel (`CLLocationCoordinate2D` isn't Equatable).
- `enum GeoSource: String, Codable { case qrz, grid, dxcc }` (pin confidence).
- `enum Maidenhead { static func center(_ grid: String) -> GeoPoint? }` — 4/6-char grid decode, used when QRZ returns `<grid>` but no lat/lon.
- View-layer-only extension `GeoPoint → CLLocationCoordinate2D` lives in StationMapView.swift.

### 2. `QRZLookup.swift` (~200 lines)
Mirrors `CallsignLookup` (actor + cache, `App/CallsignLookup.swift`) with session auth and disk persistence:
- `struct QRZStation: Codable, Sendable` — callsign, `point: GeoPoint?`, grid, name, country, source, fetched date.
- `actor QRZLookup` — `configure(username:password:)` (clears session on cred change), `isConfigured`, `station(for callsign:) async -> QRZStation?`.
- Auth: `GET https://xmldata.qrz.com/xml/current/?username=U;password=P;agent=dmrmonitor1.0` → `<Session><Key>`. Lookup: `?s=KEY;callsign=X`. Percent-encode values with `.alphanumerics` (passwords may contain `;&=`). On `Session Timeout`/missing Key: drop key, re-auth once, retry once. On `Username/password incorrect`: mark bad, stop until reconfigured. `Not found` → 24h negative cache.
- Parse with `XMLParser` delegate collecting `[String: String]` per section. `geoloc` user/grid → `.qrz`/`.grid`; dxcc → `.dxcc` (country centroid, rendered low-confidence).
- Cache: in-memory dict + `Application Support/qrzcache.json` (mirror `CallNotesStore`, `App/CallNotes.swift:52-58`), debounced writes. `inFlight: [String: Task]` collapses duplicate requests. 0.25s min-interval throttle between network hits.

### 3. `BrandmeisterLH.swift` (~280 lines)
Minimal Engine.IO v4 / Socket.IO client on `URLSessionWebSocketTask`, styled like `RewindClient` (final class, serial `DispatchQueue("bm.lh")`, reuses `LinkState`, closure callbacks, connect/disconnect):
- `struct BMCall` — sessionID, sourceID, sourceCall, sourceName?, destinationID, linkName?, start, stop? (nil = keyed up).
- Callbacks: `onState`, `onLog`, `onCalls: (([BMCall]) -> Void)` (batched every 0.5s via DispatchSourceTimer — ICMPPinger pattern). `setTalkgroups(_:)` swaps the filter without reconnecting.
- Protocol: connect `wss://api.brandmeister.network/lh/socket.io/?EIO=4&transport=websocket`; `0{json}` open → send `40`; `40{...}` ack → `.running`; `2` ping → reply `3`; `42["mqtt",payload]` events (payload may be a dict **or** a JSON-encoded string — handle both). Tolerant numeric coercion helper (Int/Double/String → UInt32) for all IDs/timestamps. `Event == "Session-Stop"` or non-zero `Stop` closes a call.
- Filter by `DestinationID ∈ talkgroups` on the socket queue before hopping to main. Refuse an empty filter set.
- Keepalive watchdog (5s tick; reconnect if no ping within pingInterval+pingTimeout). Reconnect backoff 1→30s capped, ±20% jitter, suppressed after `disconnect()`. Log first raw `42` frame (truncated) via `onLog` for schema-drift diagnostics.

### 4. `MapStation.swift` (~120 lines) — pure merge/decay logic
- `struct MapStation: Identifiable` — id ("L\(src)"/"B\(src)"), callsign, name?, dmrID, talkgroup, channel?, point, source, lastHeard, active, kind (.local/.overlay).
- `MapStationMerge.stations(heard:overlay:now:localTTL:overlayTTL:)` — one pin per station (collapse by src, newest wins), drop point-less/expired entries, local wins over overlay duplicates.

### 5. `StationMapView.swift` (~300 lines)
- iOS 17 `Map(position:selection:)` + `Annotation` with custom `StationPin` views, `.annotationTitles(.hidden)`.
- `.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))`; `.imagery` toggle behind `@AppStorage("mapStyleImagery")`. `.mapControls { MapCompass(); MapScaleView() }` — no user-location button.
- Camera: frame the pins **once** on first data (never `.automatic` steady-state — live pins would thrash the camera); "recenter" toolbar button re-fits.
- Pins: local+transmitting = `CW.green` filled w/ pulse; local recent = `CW.blue` filled; overlay = hollow `CW.green.opacity(0.7)`/`CW.dim`; `.dxcc` source = 50% opacity + dashed (country centroid). Callsign capsule label (`CW.mono(10)`) only on local + selected pins.
- Decay: 15s `Timer.publish` tick drives opacity fade (1.0→0.35 over TTL) and calls `model.pruneStations(now:)`. localTTL 60min, overlayTTL 15min, 300-pin overlay cap (evict oldest).
- Tap → bottom card via `.safeAreaInset(edge: .bottom)` (TalkBar idiom, not a sheet): callsign, name, DMR ID, TG `Tag` (reuse `ContentView.swift:483`), grid, relative time / "on air", dxcc disclaimer.
- Chrome: inline title "Map", `CW.bg` toolbar background (LogView pattern, `ContentView.swift:406-408`). Toolbar: TG filter Menu, style toggle, recenter. Status strip (`CW.mono(11)`): "BM · 42 stations · 7 local" + link state. `CW.amber` banner when QRZ unconfigured: "Add QRZ credentials in Settings to plot stations."
- Lifecycle: `.task { model.startBMFeed(settings) }`, `.onDisappear { model.stopBMFeed() }`, `scenePhase` handling. **Overlay socket runs only while the map is visible** (the raw stream is all of BM — battery/data cost). `.task` also calls `model.backfillCoordinates()` once.

## Modified files

### `Settings.swift`
Add `@AppStorage`: `qrzUser`, `qrzPassword` (plain AppStorage matches existing hotspot-password precedent — no Keychain in this codebase), `mapOverlay = true`, `mapOverlayTG = 0` (0 = follow my talkgroups). Computed: `qrzConfigured`, `mapOverlayTalkgroups: Set<UInt32>` (`mapOverlayTG > 0 ? [it] : Set(activeTalkgroups)` — `activeTalkgroups` verified at Settings.swift:138).

### `MonitorModel.swift`
- `HeardEntry`: add `var point: GeoPoint?`, `var geoSource: GeoSource?`.
- New members: `private let qrz = QRZLookup()`, `bmClient: BrandmeisterLH?`, `@Published var bmStations: [UInt32: BMStation]`, `@Published var bmState: LinkState`, `overlayGeocodeTried: Set<String>`, `maxOverlay = 300`.
- **Geocode eagerly** in the existing `openCall` lookup Task (~line 353): after callsign resolves, `await qrz.station(for:)`, re-find entry by id (may have been evicted across the await), set point (falling back to `Maidenhead.center(grid)`). Same in `openDStarCall` (~177, callsign known up front). Skip when `!qrz.isConfigured`. Rationale: bounded (one lookup per new unique station, cache absorbs repeats); lazy-on-map-open would burst ~100 QRZ hits at once.
- `applyQRZ(_ settings:)` called from `connect(_:)` and Settings `.onChange`; `backfillCoordinates()` (unique point-less callsigns from `heard`, cap 40, serial — actor throttle paces it); `startBMFeed`/`stopBMFeed`/`setBMFilter`/`clearOverlay`; `applyBMCalls(_:)` (upsert by SourceID, evict past cap, geocode new callsigns once per session); `pruneStations(now:)` (TTL eviction + force-clear `active` on BM calls with no Session-Stop after 300s).
- `disconnect()` must NOT touch the BM feed (map works without a master link) — comment this.
- If `type_body_length` lint trips, put BM-feed methods in a `MonitorModel+Overlay.swift` extension.

### `ContentView.swift`
- Toolbar (~line 118): new `ToolbarItem(placement: .topBarTrailing)` before the gear — `NavigationLink { StationMapView() } label: { Image(systemName: "map") }`.
- SettingsView (~line 669, near Data section): new "QRZ" section — `TextField("QRZ username")` + `SecureField("QRZ password")`, footer "Used to place stations on the map. A QRZ subscription is required for coordinates.", `.onChange` → `model.applyQRZ(settings)`.

### `README.md` — short "Map" section (QRZ subscription requirement, TG filter, overlay only runs while map is on screen).

## Implementation order (build after each step)

1. GeoPoint.swift → 2. Settings fields → 3. QRZLookup.swift → 4. MonitorModel QRZ wiring → 5. Settings UI; **checkpoint: `xcodegen generate && xc deploy`, enter creds, verify coordinates resolve (temp log) before any map code** → 6. MapStation.swift → 7. StationMapView.swift + toolbar entry (local pins only); **checkpoint: deploy, heard stations plot** → 8. BrandmeisterLH.swift; **verify handshake + log first raw frame before finalizing the parser** → 9. overlay wiring + TG menu + status strip → 10. `xcodegen generate` + full quality gate → 11. README + CHANGELOG-if-present; commit per step or at checkpoints.

## Verification

- `xcodegen generate`; `xc build` warning-free; `xc lint` ≤ 161 baseline (watch `file_length` on StationMapView, `type_body_length` on MonitorModel; no <3-char identifiers).
- `xc deploy` to theseus, then on device: no creds → amber banner, no crash; bad creds → single log error, no retry storm (`xc logs DMRMonitor`); good creds on busy TG → blue pins appear, green while keyed; overlay accumulates dim pins; wifi kill → backoff reconnect (1/2/4s in log), recovery without relaunch; background 60s → clean reconnect, no duplicate sockets; pop map → socket closes, pins persist on re-entry; 20min soak → pins fade/prune, flat memory; smooth pan with 200+ pins; callout correct at any zoom.

## Top risks

1. **QRZ rate limiting/ban** from overlay geocoding on a busy TG. Mitigations (all required): disk cache, 24h negative cache, once-per-session tried-set, 0.25s throttle, overlay defaults to the user's own (usually single) TG. Fallback: lazy geocode-on-tap for overlay pins.
2. **BM `mqtt` schema/transport is undocumented and has drifted** (dict vs JSON-string payloads, field casing). Mitigations: log first raw frame, tolerant coercion, no force-unwraps, overlay behind `settings.mapOverlay` so breakage degrades to local-pins-only.
3. **Map perf/camera thrash** with live annotations. Mitigations: 300-pin cap, one pin per station, 15s coarse tick, stable identities, labels only on local/selected, camera frozen after first fit.
