# Buddy Watch: server-side push for DMRMonitor

## Context

A beta user (Winnippeger) asked for RadioID-style "buddy watch": get notified when watched callsigns key up on BrandMeister, with push notifications. User chose server-side push (true 24/7, app closed). Second request — a DMR nets calendar — is deferred: research confirmed no machine-readable net-schedule source exists (dvnets.com has the data but no API; NetLogger's open API is HF/SSB only), so nets will be manual entry + local reminders later, ideally after asking the dvnets operator for a feed. Copy this plan to `DMRMonitor/docs/plans/2026-09-08-buddy-watch.md` at implementation start.

**Verified facts:** BM firehose = `42["join","everything"]` on wss://api.brandmeister.network/lh/socket.io (~11 events/sec measured). APNs `.p8` keys are team-scoped; the working hearth key (`43LTNHUD6Y`, team `7UE4RDLUSX` — verified in ansible-blackpearl host_vars, hearth/ios/project.yml, and DMRMonitor/project.yml) reuses fine for `com.carrierwave.DMRMonitor`. Do NOT mint a second key (Apple caps at 2). Working APNs client to crib: `hearth/crates/hearth-orchestrator/src/push.rs` (ES256 JWT cache 50min, reqwest rustls+h2, dead-token pruning on 410/BadDeviceToken/Unregistered — keep its tests). iOS push manager to port: `hearth/ios/Urithiru/Push/PushManager.swift` (minus action categories).

## Server: new public repo `dmr-lookout` (Rust)

Layout: `src/{main,config,feed,event,watch,db,push,api}.rs`, `migrations/0001_init.sql`, `tests/fixtures/lh_frames.jsonl` (~60s captured frames). Deps: tokio, tokio-tungstenite(rustls), axum 0.7, sqlx(sqlite), reqwest(rustls,http2), jsonwebtoken 9, serde, chrono, tracing, anyhow.

- **feed.rs**: port framing from `DMRMonitor/App/BrandmeisterLH.swift:160-231` — "0"→parse ping intervals, send "40"; "40"→join `everything`; "2"→"3"; "42"→mqtt double-unwrap (dict-or-JSON-string wrapper AND payload); tolerant numeric coercion (Int/Double/String). Backoff min(30s, 2^n)·jitter; 5s stall watchdog on pingInterval+pingTimeout. **No `searchHouse`** — history must never push. Loop shape precedent: `carrier_wave/server/src/rbn/ingester.rs`.
- **Storage**: SQLite at `/opt/dmr-lookout/data/lookout.db` (≪50 rows; postgres would be pure coupling). Hot path never queries: `ArcSwap<WatchIndex>` with `by_id: HashMap<u32,_>` and `by_call: HashMap<String,_>` (normalized: uppercase, truncate at first `/` or `-`), rebuilt on boot + every watchlist write. Cooldown state in-memory, written through so restarts don't re-notify.
- **Notify rules (v1 exact)**: Session-Start only (Event=="Session-Start" or absent+Stop==0); drop events with Start older than 120s; 10s post-connect grace; per-(device,watch) cooldown 1800s; per-device cap 12 pushes/hour; quiet-hours columns shipped but default off; optional per-watch TG filter (empty=any). Match on normalized callsign AND SourceID independently (blank SourceCall still matches by ID).
- **APNs payload**: title "W1ABC on TG 3100", body "Name · TG name"; custom keys call/dmr_id/tg; `apns-collapse-id: buddy-<call>`, `apns-push-type: alert`, priority 10, topic com.carrierwave.DMRMonitor, thread-id "buddy", interruption-level time-sensitive.
- **API (axum, bind 127.0.0.1:8084)**: `GET /v1/health` (open: feed_connected, last_event_ago_secs, apns_host, counts, version); bearer-token middleware on the rest: `POST /v1/devices` (upsert {device_id, apns_token, platform, app_version}), `GET|PUT /v1/devices/:id/watches` (PUT = whole-list replace), `DELETE /v1/devices/:id`, `POST /v1/devices/:id/test` (test push — key verification route).
- **Auth**: single static bearer (`LOOKOUT_API_TOKEN` env, vaulted) + per-device UUID minted by the app. App is source of truth for the watch list (whole-list PUT, no merge logic).

## Hosting: Hetzner VPS, `dmr.carrierwave.app`

Phone must register from cellular; blackpearl's WiFi-only link is the wrong place for the one component that must be reachable (pushes are outbound-only, but registration isn't). Role `carrier_wave/infra/ansible/roles/dmr_lookout/` cloned structurally from `roles/cw_swl` (public GitHub release tarball → /opt, config.toml + env template, systemd Restart=always, nginx+certbot two-phase) plus: the `.p8` copy task verbatim from `ansible-blackpearl/roles/hearth/tasks/main.yml:85-93`, and the retrying `uri` health check from `roles/activities_server`. Release binary: **musl** x86_64 (hearth precedent, no glibc coupling).

APNs key wiring: the two ansible repos have separate vaults — decrypt the `.p8` from ansible-blackpearl's vault, add as `vault_dmr_lookout_apns_key` to `carrier_wave/infra/ansible/group_vars/hetzner_servers/vault.yml`; non-secret ids (`43LTNHUD6Y` / `7UE4RDLUSX` / bundle id / `production: false`) in main.yml. **Comment in both repos that the key is duplicated** (rotation touches both). Porkbun A record for `dmr.carrierwave.app` BEFORE certbot runs (porkbun-dns skill).

## iOS app

- **project.yml**: `entitlements: {path: App/DMRMonitor.entitlements, properties: {aps-environment: development}}` + exclude from sources; gitignore the generated file; `xcodegen generate`. `development` is REQUIRED — dev-signed builds vend sandbox tokens; server `production=false` → api.sandbox.push.apple.com. Mismatch doesn't just fail: BadDeviceToken prunes the device row. Log apns_host at boot; show it in /v1/health.
- **App/PushRegistrar.swift** (~90 lines): port Urithiru PushManager/PushDelegate — request permission only on first enable (never at launch), `registerForRemoteNotifications()` idempotently per launch when enabled, willPresent → [.banner, .sound]. `@UIApplicationDelegateAdaptor(PushDelegate.self)` one-liner in DMRMonitorApp.swift.
- **App/BuddyWatch.swift** (~160 lines): `Buddy {id, callsign, dmrID, label, talkgroups}` Codable with lenient decoder (Talkgroup pattern, Settings.swift:29-35); `BuddyClient` (@MainActor ObservableObject): registerDevice/putWatches/deleteDevice/sendTest via URLSession.
- **App/BuddyListView.swift** (~150 lines): editor cloned from the Talkgroups editing block (ContentView ~675-700): callsign+name TextFields, onDelete, "Add buddy", status row + "Send test notification". Resolve callsign→DMR ID at add time via radioid.net `?callsign=` (invert the existing CallsignLookup direction) and store both.
- **Settings.swift**: `buddyWatchEnabled=false`, `buddyServerURL="https://dmr.carrierwave.app"`, `buddyAPIToken`, `buddyDeviceID`, `buddyLastToken`, `buddyLastSynced`, `buddiesJSON` + `buddyList` accessor (talkgroupList pattern, lines 81-92).
- **SettingsView section** (~14 lines after the QRZ section): Toggle → NavigationLink "Buddies (N)" + server URL + SecureField token; footer explains.
- **Lifecycle**: toggle-on mints UUID + enables push; token arrival → POST device → PUT watches; every launch re-register, re-POST only if token hex changed; re-PUT on BuddyListView dismiss + scenePhase active when list hash differs; toggle-off best-effort DELETE. Notification tap just opens the app (no deep link v1).
- Gates: all new files <200 lines, no <3-char identifiers, lint stays at 161 baseline, warning-free build.

## Ordered steps

S1 (M): repo scaffold + config + health + GitHub Actions musl release workflow.
S2 (M): feed.rs + event.rs port; capture fixtures; parser/reconnect tests.
S3 (S): db + matcher + index; rule unit tests (cooldown, Stop ignored, TG filter, /P normalization, blank-call-by-ID).
S4 (S): push.rs cribbed from hearth + collapse-id; keep tests.
S5 (S): api.rs routes + bearer middleware + index rebuild on write.
**S6 (M): iOS push plumbing FIRST, before any UI** — entitlements, xcodegen, PushRegistrar, adaptor; then ONE `xcodebuild ... -allowProvisioningUpdates build` (xc doesn't pass it) to register the explicit App ID + push capability. Highest-risk step: if com.carrierwave.DMRMonitor only ever rode a wildcard profile, push may force choices (hearth's exact scar) — if the bundle id must change, UserDefaults resets, so screenshot Settings first.
S7 (M): Buddy model + Settings + BuddyClient + BuddyListView + Settings section; build + lint gates.
S8 (S): local E2E on wifi: test-push route, watch own callsign, key up from app TX on a quiet TG, cooldown check (3 keys in 60s → 1 push), locked/force-quit delivery.
S9 (M): ansible role + vault key copy + porkbun A record + site.yml block.
S10 (S): tag v0.1.0, fill version/checksum, `ansible-playbook -i inventory/hosts.yml site.yml --tags dmr-lookout --vault-password-file ~/ansible_pass`; `curl https://dmr.carrierwave.app/v1/health` from cellular; point app at real URL; `xc deploy`; restart-safety + dead-token-prune checks.

## Top risks

1. Explicit App ID / push capability provisioning (S6 first; hearth had to change bundle id for this).
2. Sandbox/production mismatch silently prunes devices (log + health-expose apns_host; never flip production for dev-signed builds).
3. BM may frown on a permanent `everything` subscriber (~1M events/day). Build the dst_<tg> room path from day one; use it when every watch has a TG filter.
4. Notification fatigue on nets — cooldown + collapse-id + hourly cap; verify against a genuinely busy buddy.
5. Stalled-but-connected feed — watchdog + last_event_ago_secs on /v1/health; optionally ntfy alert (ntfy infra exists on blackpearl).
6. `.p8` duplicated across two vaults — comment both sides.
7. Shared bearer token — acceptable for personal service; nginx limit_req on /v1/.

## Deferred: nets calendar

Manual net entries + local scheduled reminders (UNCalendarNotificationTrigger), JSON import/export for sharing; optionally cross-check "live now" via BM/TGIF active-TG APIs before firing. Draft an outreach message to the dvnets.com operator (LZARC LLC, via /submit) asking about a feed — their data model matches exactly.
