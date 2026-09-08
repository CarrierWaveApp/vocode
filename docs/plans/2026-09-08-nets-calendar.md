# DMRMonitor: Nets calendar (manual entry + local reminders + join)

## Context

Winnippeger's second request: a DMR nets calendar with reminders "5, 10 min before, or right now", because people will use the app to join nets. No external schedule API exists (dvnets researched — none), so v1 = manual entry, local notifications (offline), JSON share/import for club distribution, and a one-tap Join that switches the talkgroup live and connects. Decided: main-screen "// NETS" section + full editor screen; per-net leads {10, 5, 0}; JSON sharing in v1. Copy this plan to `docs/plans/2026-09-08-nets-calendar.md` at start.

**S0 (leftover from buddy watch):** deploy dmr-lookout v0.1.1 (CI already green): update `carrier_wave/infra/ansible/roles/dmr_lookout/defaults/main.yml` version to 0.1.1 + new sha256 from the release's checksums.txt, commit, push, `ansible-playbook -i inventory/hosts.yml site.yml --tags dmr-lookout --vault-password-file ~/ansible_pass`, verify `/v1/health` shows 0.1.1.

## Model + schedule math (`App/Nets.swift`, ~180 lines, Foundation-only)

`Net {id: UUID (merge key), name, network (label), tg: UInt32, weekdays: [Int] (1=Sun…7=Sat), hour, minute, timeZoneID (IANA, default current), durationMin (default 60, drives "live now" only), leads: [Int] ⊆ [10,5,0], enabled, notes}` — lenient `init(from:)` per Talkgroup (Settings.swift:26-35), every field `decodeIfPresent ?? default` incl. tg (filter tg>0 at display, never throw away an import). `NetsFile {version:1, nets:[Net]}` envelope with bare-array decode fallback.

`NetSchedule`: `nextOccurrence(of:after:)`, `occurrences(of:after:limit:)`, `isLive(_:at:)`, `countdown(to:from:)`. Use `Calendar(identifier:.gregorian)` with `cal.timeZone = net.timeZone` + `cal.nextDate(after:matching: [hour,minute,weekday], matchingPolicy: .nextTime)` per weekday, min wins. **Zone on the Calendar for nextDate; zone on the DateComponents for UNCalendarNotificationTrigger — the two APIs have opposite conventions; this is THE wrong-hour bug source. Unit-test it.**

**Test target (new):** `project.yml` `DMRMonitorTests: {type: bundle.unit-test, platform: iOS, sources: [Tests], dependencies: [target: DMRMonitor]}` + `Tests/NetScheduleTests.swift`. Run on the SIMULATOR (`xcodebuild test -scheme DMRMonitor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`) — xc test targets the device and drags test-host signing into provisioning. Cases: DST spring-forward (America/Denver 19:00), UTC 01:00Z crossing the local day boundary, multi-weekday min selection, lead subtraction rolling to the previous weekday (00:05−10min).

## Scheduling + join (`App/NetScheduler.swift`, ~170 lines)

- IDs `net.<uuid>.<weekday>.<lead>`; reschedule = getPendingNotificationRequests → remove ids with prefix `net.` → rebuild (no prefix-removal API exists). Per (net×weekday×lead): compute the concrete next occurrence, subtract lead, extract [weekday,hour,minute] in the net's zone (day-rollover falls out free), set `comps.timeZone`, `UNCalendarNotificationTrigger(repeats: true)`.
- **64-cap**: expand nets in list order, stop at 64; `pendingCount` for the UI footer "N / 64 reminders" + trimmed warning. Repeating triggers are otherwise invisible.
- Content: title "Net: <name>", body "TG <tg> · starts in 10 min"/"· starting now", `categoryIdentifier: "NET"`, `threadIdentifier: "nets"`, userInfo {kind:"net", netID, tg, name}. NO time-sensitive interruption level (needs another entitlement/provisioning round-trip).
- Reschedule call sites (explicit, never off `onChange(of: netsJSON)` — AppStorage writes per keystroke): launch, scenePhase→active, NetEditView.onDisappear, enable toggle, delete, import completion.
- `NetJoin.join(tg:name:settings:model:)`: append `Talkgroup(tg:, name:, listen: .off)` if absent (setListen bails on unknown TG), `settings.setListen(tg, .live)` (singleTG collapse + txTarget), then `model.isConnected && netMode == "openterminal"` → `applyListenStates` (live OTP diff; homebrew ships TGs at login → must reconnect) else `model.connect(settings)`. D-STAR mode: hide Join (no talkgroups).
- `NetJoinRelay` ViewModifier applied in **DMRMonitorApp.swift** (root, never unloaded — NOT in the lazy List section): drains UserDefaults pendingJoinTG/Name on .task, scenePhase→active, and a NotificationCenter post. Both channels needed: cold-launch (didReceive before any .task → UserDefaults) and already-foreground (no scenePhase change → post).

## PushRegistrar changes

Split `requestAuthorization() async -> Bool` (the notDetermined/denied switch, NO remote registration) out of `enable()`; enable = requestAuthorization + registerForRemoteNotifications (buddy watch unchanged; either enable order works). In didFinishLaunching: `setNotificationCategories` with "NET" category, action `NET_JOIN` "Join" options `[.foreground]`. Add `didReceive`: for kind=="net" and action ∈ {NET_JOIN, default}: write UserDefaults + post NotificationCenter name.

## UI (all new files; ContentView gets ONE line)

- `App/NetsSection.swift` (~140): `body` IS a `Section` — insert `NetsSection()` in ContentView's List between Talkgroups and Activity. ≤2 upcoming nets with `NetCountdown` (own `TimelineView(.periodic(by: 30))`), Join pill (PillButtonStyle), NavigationLink → NetsView, empty state row.
- `App/NetsView.swift` (~200): list (enable toggles, swipe delete, Add), `ShareLink` export via `Transferable`/`DataRepresentation(exportedContentType: .json)` `.suggestedFileName("dmr-nets.json")` (no temp files), `.fileImporter([.json])` wrapped in `startAccessingSecurityScopedResource`, merge by id (replace on match, append on new), alert "Imported 6 nets (2 updated)", reminder counter footer, permission-denied row → `UIApplication.openSettingsURLString`. `import UniformTypeIdentifiers`.
- `App/NetEditView.swift` (~180): name/network/TG fields (talkgroups editor idioms, CW.mono), DatePicker(.hourAndMinute) round-tripped through DateComponents, 7 weekday chips multi-select, curated timezone Picker (UTC + US zones + Europe/London + current + the net's own id unioned in), duration Stepper, three lead Toggles, notes; `.onDisappear` reschedule.
- `Settings.swift`: `@AppStorage("netsJSON")` + `netList` accessor copied from **buddyList** (it already uses the lint-preferred `String(bytes:encoding:)`).
- No seed data — a stale builtin schedule is worse than empty; the JSON export IS the distribution channel.

## Ordered steps

S0 server v0.1.1 deploy (above) → S1 Settings + Nets.swift + test target + sim tests green → S2 NetScheduler + PushRegistrar split/category/didReceive + relay line in DMRMonitorApp → S3 NetEditView + NetsView reachable from Settings; **verify a real banner on device here** (highest-risk unknown, don't wait behind polish) → S4 NetsSection + ContentView one-liner (keep a Settings NavigationLink as second path) → S5 export/import → S6 gates: `xcodegen generate`, `xc build` warning-free, `xc lint` == 161 baseline (NO xc format — swiftformat fights swiftlint in this repo), sim tests, `xc deploy`, commit.

## Device verification

Net 12 min out, all three leads → footer +3; background → banner at T−10; lock screen banner; long-press → Join → TG live + link connects; force-quit → next lead → Join cold-launches and still joins (UserDefaults path); toggle off → pending −3; export → Files → re-import → no dupes; edit + re-import → updated in place; change device timezone → countdown shifts, net's displayed wall time doesn't; fresh-install order check (nets permission first, buddy watch after → APNs still registers).

## Top risks

1. Permission interplay with buddy watch — split authorization from registration; test both enable orders.
2. 64-request cap (3 daily nets × 3 leads overflows) — deterministic trim + visible counter.
3. Timezone/DST — opposite zone conventions between Calendar.nextDate and UNCalendarNotificationTrigger; unit-tested; spring-forward-straddling lead accepted + commented.
4. ContentView size gates — one-line insert, everything else in new files; verify lint 161 after.
5. Join per net mode — homebrew reconnects, D-STAR hides Join; wrong handling makes Join a silent no-op for hotspot users.
