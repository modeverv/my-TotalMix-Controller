import SwiftUI

struct MainView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var midi: MIDIManager
    @EnvironmentObject private var osc: OSCManager
    @State private var showsSettings = false
    var body: some View {
        GeometryReader { geometry in
            let visibleNumbers = settings.visibleSnapshotNumbers
            let maximumColumns = geometry.size.width > geometry.size.height * 1.15 ? 4 : 2
            let columns = max(1, min(maximumColumns, visibleNumbers.count))
            let rows = max(1, (visibleNumbers.count + columns - 1) / columns)
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TotalMix").font(.system(size: 25, weight: .semibold))
                        Text("SNAPSHOT TOUCH").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showsSettings = true } label: {
                        Label("設定", systemImage: "gearshape").padding(.horizontal, 10).frame(minHeight: 36)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    .buttonStyle(.bordered)
                }
                if visibleNumbers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "eye.slash").font(.largeTitle).foregroundStyle(.secondary)
                        Text("すべてのSnapshotが非表示です")
                        Button("設定で再表示する") { showsSettings = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { grid in
                        let cellHeight = max(150, (grid.size.height - CGFloat(rows - 1) * 14) / CGFloat(rows))
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: 14) {
                                ForEach(visibleNumbers, id: \.self) { number in
                                    SnapshotButton(number: number, name: settings.name(for: number), lastSent: midi.lastSentSnapshot == number, enabled: midi.isConnected) {
                                        // Also guard actions retained during a view update.
                                        if !settings.hiddenSnapshots.contains(number) { midi.recall(number) }
                                    }
                                    .frame(height: cellHeight)
                                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [])
                                    .disabled(showsSettings)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                MonitorControlsView().disabled(showsSettings)
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(midi.isConnected ? Color.mint : Color.orange).frame(width: 8, height: 8).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(midi.errorMessage ?? "MIDI: \(midi.selectedDestination?.displayName ?? "未接続")")
                            .foregroundStyle(midi.errorMessage == nil ? Color.secondary : Color.orange)
                        Text("強調表示は最後に送信したSnapshotです。TotalMixの現在状態とは同期しません。")
                            .foregroundStyle(.secondary)
                    }.font(.system(size: 11))
                    Spacer(minLength: 0)
                    if let date = midi.lastSentDate {
                        Text(date, style: .time).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 500)
        .background(Color(red: 0.045, green: 0.065, blue: 0.085))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
            SettingsView().environmentObject(settings).environmentObject(midi).environmentObject(osc)
        }
    }
}
