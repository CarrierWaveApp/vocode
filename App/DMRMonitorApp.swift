import SwiftUI

@main
struct DMRMonitorApp: App {
    // MARK: Lifecycle

    init() {
        let store = CallNotesStore()
        _notes = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: MonitorModel(notes: store))
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView()
                // NetJoinRelay reads these objects, so it must sit inside
                // the environmentObject injections, not above them
                .modifier(NetJoinRelay())
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(notes)
        }
    }

    // MARK: Private

    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @StateObject private var model: MonitorModel
    @StateObject private var settings = Settings()
    @StateObject private var notes: CallNotesStore
}
