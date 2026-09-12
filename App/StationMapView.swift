import MapKit
import SwiftUI

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - StationMapView

/// Full-screen map of heard stations plus the BrandMeister overlay
struct StationMapView: View {
    // MARK: Internal

    @EnvironmentObject var model: MonitorModel
    @EnvironmentObject var settings: Settings
    @ObservedObject var overlay: OverlayModel

    var body: some View {
        Map(position: $camera, selection: $selected) {
            ForEach(stations) { station in
                Annotation("", coordinate: station.point.coordinate) {
                    StationPin(
                        station: station,
                        isSelected: selected == station.id,
                        fade: fade(for: station)
                    )
                }
                .tag(station.id)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(imagery
            ? .imagery
            : .standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top, spacing: 0) { statusStrip }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let station = stations.first(where: { $0.id == selected }) {
                StationCard(station: station, now: now, tgName: settings.tgName) {
                    selected = nil
                }
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .preferredColorScheme(.dark)
        .onReceive(tick) { date in
            now = date
            overlay.prune(now: date)
        }
        .onChange(of: stations.isEmpty) { _, empty in
            if !empty, !framed {
                framed = true
                recenter()
            }
        }
        .task {
            model.applyQRZ(settings)
            startFeed()
            await model.backfillCoordinates()
        }
        .onDisappear { overlay.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startFeed()
            } else {
                overlay.stop()
            }
        }
    }

    // MARK: Private

    private static let worldRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30, longitude: -40),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 220)
    )

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mapStyleImagery") private var imagery = false
    @State private var camera: MapCameraPosition = .region(Self.worldRegion)
    @State private var framed = false
    @State private var selected: String?
    @State private var now = Date()

    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private let localTTL: TimeInterval = 60 * 60
    private let overlayTTL: TimeInterval = 15 * 60

    private var stations: [MapStation] {
        MapStationMerge.stations(
            heard: model.heard, overlay: overlay.stations,
            now: now, localTTL: localTTL, overlayTTL: overlayTTL
        )
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Overlay talkgroup", selection: settings.$mapOverlayTG) {
                    Text("Follow my talkgroups").tag(0)
                    ForEach(settings.talkgroupList.filter { $0.tg > 0 }) { group in
                        Text(tgLabel(group)).tag(Int(group.tg))
                    }
                }
                Toggle("Satellite", isOn: $imagery)
                Toggle("BM overlay", isOn: settings.$mapOverlay)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .onChange(of: settings.mapOverlayTG) {
                overlay.setTalkgroups(settings.mapOverlayTalkgroups)
            }
            .onChange(of: settings.mapOverlay) { _, enabled in
                if enabled {
                    startFeed()
                } else {
                    overlay.stop()
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { recenter() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
    }

    private var overlayColor: Color {
        switch overlay.state {
        case .running: CW.green
        case .idle: CW.xdim
        case .failed: CW.red
        default: CW.amber
        }
    }

    private var overlayStateText: String {
        if case let .failed(why) = overlay.state {
            return why
        }
        return overlay.state == .running ? "live" : String(describing: overlay.state)
    }

    private var statusStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if settings.mapOverlay {
                    Circle()
                        .fill(overlayColor)
                        .frame(width: 6, height: 6)
                    Text("BM \(overlayStateText)")
                        .foregroundStyle(CW.dim)
                }
                Spacer()
                Text("\(stations.filter { $0.kind == .overlay }.count) network · " +
                    "\(stations.filter { $0.kind == .local }.count) heard")
                    .foregroundStyle(CW.dim)
            }
            .font(CW.mono(11))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(CW.bg.opacity(0.9))
            if !settings.qrzConfigured {
                Text("Add QRZ credentials in Settings to plot stations")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.amber)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(CW.amber.opacity(0.12))
            }
        }
    }

    private func startFeed() {
        guard settings.mapOverlay else {
            return
        }
        overlay.start(talkgroups: settings.mapOverlayTalkgroups)
    }

    /// Older pins fade toward 0.35 across their TTL
    private func fade(for station: MapStation) -> Double {
        guard !station.active else {
            return 1
        }
        let ttl = station.kind == .local ? localTTL : overlayTTL
        let fraction = min(1, station.age(at: now) / ttl)
        return 1 - 0.65 * fraction
    }

    private func recenter() {
        let points = stations.map(\.point)
        guard let first = points.first else {
            return
        }
        var minLat = first.lat, maxLat = first.lat
        var minLon = first.lon, maxLon = first.lon
        for point in points.dropFirst() {
            minLat = min(minLat, point.lat)
            maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon)
            maxLon = max(maxLon, point.lon)
        }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(4, (maxLat - minLat) * 1.4),
                longitudeDelta: max(4, (maxLon - minLon) * 1.4)
            )
        )
        withAnimation { camera = .region(region) }
    }

    private func tgLabel(_ group: Talkgroup) -> String {
        group.name.isEmpty ? "TG \(group.tg)" : "TG \(group.tg) \(group.name)"
    }
}

// MARK: - StationPin

private struct StationPin: View {
    // MARK: Internal

    let station: MapStation
    let isSelected: Bool
    let fade: Double

    var body: some View {
        VStack(spacing: 3) {
            pin
            if station.kind == .local || isSelected {
                Text(station.callsign)
                    .font(CW.mono(10, medium: true))
                    .foregroundStyle(CW.text)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(CW.surface.opacity(0.9))
                    .overlay(Capsule().stroke(CW.border, lineWidth: 1))
                    .clipShape(Capsule())
            }
        }
        .opacity(station.source == .dxcc ? fade * 0.5 : fade)
    }

    // MARK: Private

    @ViewBuilder
    private var pin: some View {
        let color = station.active ? CW.green : (station.kind == .local ? CW.blue : CW.dim)
        if station.kind == .local {
            Circle()
                .fill(color)
                .frame(width: station.active ? 12 : 10, height: station.active ? 12 : 10)
                .overlay(Circle().stroke(CW.bg, lineWidth: 1.5))
                .shadow(color: station.active ? CW.green.opacity(0.8) : .clear, radius: 5)
        } else {
            Circle()
                .stroke(color.opacity(station.active ? 0.9 : 0.7),
                        style: StrokeStyle(lineWidth: station.active ? 2 : 1.5,
                                           dash: station.source == .dxcc ? [2, 2] : []))
                .frame(width: station.active ? 10 : 8, height: station.active ? 10 : 8)
        }
    }
}

// MARK: - StationCard

private struct StationCard: View {
    // MARK: Internal

    let station: MapStation
    let now: Date
    let tgName: (UInt32) -> String?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(station.callsign)
                    .font(CW.sans(20, .semibold))
                    .foregroundStyle(CW.white)
                if let name = station.name {
                    Text(name)
                        .font(CW.sans(14))
                        .foregroundStyle(CW.dim)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CW.dim)
                }
            }
            HStack(spacing: 8) {
                if let channel = station.channel {
                    Tag(channel, color: CW.blue)
                } else if station.talkgroup > 0 {
                    Tag(tgName(station.talkgroup).map { "TG \(station.talkgroup) \($0)" }
                        ?? "TG \(station.talkgroup)", color: CW.blue)
                }
                if station.dmrID > 0 {
                    Text(String(station.dmrID))
                        .font(CW.mono(12))
                        .foregroundStyle(CW.dim)
                }
                Spacer()
                if station.active {
                    Text("on air")
                        .font(CW.mono(12, medium: true))
                        .foregroundStyle(CW.green)
                } else {
                    Text(relative(station.lastHeard))
                        .font(CW.mono(12))
                        .foregroundStyle(CW.dim)
                }
            }
            if station.source == .dxcc {
                Text("Approximate: country center only")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.amber)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CW.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(CW.border), alignment: .top)
    }

    // MARK: Private

    private func relative(_ date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds)s ago"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m ago"
        }
        return "\(seconds / 3_600)h \(seconds % 3_600 / 60)m ago"
    }
}
