import SwiftUI

struct IOSMainView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var osc: OSCManager
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsSettings = false
    @State private var checkedSetup = false
    private let background = Color(red: 0.045, green: 0.065, blue: 0.085)

    var body: some View {
        GeometryReader { geometry in
            let columns = typeSize.isAccessibilitySize ? 1 : (geometry.size.width > 650 ? 4 : 2)
            VStack(spacing: 16) {
                header
                connectionStatus
                ScrollView {
                    VStack(spacing: 22) {
                        if settings.visibleSnapshotNumbers.isEmpty {
                            emptySnapshots
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                                ForEach(settings.visibleSnapshotNumbers, id: \.self) { number in
                                    snapshot(number)
                                }
                            }
                            .accessibilityIdentifier("snapshotGrid")
                        }
                        IOSMonitorControlsView()
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(background.ignoresSafeArea())
        .sheet(isPresented: $showsSettings) {
            IOSSettingsView().environmentObject(settings).environmentObject(osc)
        }
        .onAppear {
            guard !checkedSetup else { return }
            checkedSetup = true
            showsSettings = settings.oscHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TotalMix").font(.title.bold())
                Text("SNAPSHOT TOUCH")
                    .font(.caption2.monospaced().weight(.medium)).tracking(2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape").font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("設定")
            .accessibilityIdentifier("settings.open")
        }
    }

    private var connectionStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(osc.connected ? Color.mint : Color.orange)
                .frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(osc.connected ? "OSC同期中" : (settings.oscEnabled ? "接続を確認してください" : "OSCは無効です"))
                    .font(.subheadline.weight(.semibold))
                Text(osc.errorMessage ?? (osc.connected ? "TotalMixから受信した状態を表示しています" : "同じWi-Fiに接続し、設定からMacを指定してください"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connection.status")
    }

    private var emptySnapshots: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("すべてのSnapshotが非表示です").multilineTextAlignment(.center)
            Button("設定で再表示する") { showsSettings = true }.buttonStyle(.borderedProminent)
                .accessibilityIdentifier("restoreSnapshotsButton")
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func snapshot(_ number: Int) -> some View {
        let selected = osc.currentSnapshot == number
        return Button { osc.recallSnapshot(number) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Text(String(format: "%02d", number)).font(.system(.title, design: .rounded).weight(.light))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint).font(.title3) }
                }
                Text(settings.name(for: number)).font(.headline).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(selected ? "選択中" : "SNAPSHOT \(number)")
                    .font(.caption2.monospaced().weight(.medium))
                    .foregroundStyle(selected ? Color.mint : Color.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(IOSPanelButtonStyle(selected: selected))
        .disabled(!osc.connected)
        .opacity(osc.connected ? 1 : 0.5)
        .accessibilityLabel("Snapshot \(number)、\(settings.name(for: number))")
        .accessibilityValue(selected ? "選択中" : "未選択")
        .accessibilityIdentifier("snapshot.\(number)")
    }
}

private struct IOSPanelButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.mint.opacity(0.25) : Color.white.opacity(selected ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.mint : Color.white.opacity(0.10), lineWidth: selected ? 2 : 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct IOSMonitorControlsView: View {
    @EnvironmentObject private var osc: OSCManager
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var dragging = false
    @State private var draftVolume = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MONITOR").font(.caption.monospaced().weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            let columns = typeSize.isAccessibilitySize ? 1 : 3
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                toggle("M1 MUTE", icon: "speaker.slash.fill", value: osc.muteGroup1, pending: osc.pendingMute, id: "monitor.mute", action: osc.toggleMuteGroup1)
                toggle("DIM", icon: "speaker.wave.1.fill", value: osc.dim, pending: osc.pendingDim, id: "monitor.dim", action: osc.toggleDim)
                Button(action: osc.setMainVolumeToZeroDB) {
                    VStack(spacing: 8) {
                        Text("Fader 1").font(.caption.weight(.semibold))
                        Text("0 dB").font(.headline.monospaced())
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(IOSPanelButtonStyle())
                .disabled(!osc.canAdjustVolume)
                .accessibilityLabel("Fader 1を0 dBに設定")
                .accessibilityIdentifier("monitor.unity")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Fader 1 VOLUME").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(osc.volumeLabel).font(.title3.monospaced().weight(.medium))
                        .accessibilityIdentifier("volumeLabel")
                }
                Slider(value: Binding(
                    get: { dragging ? draftVolume : osc.mainVolume ?? draftVolume },
                    set: { draftVolume = $0; osc.setMainVolume($0) }
                ), in: 0...1, onEditingChanged: { editing in
                    dragging = editing
                    if !editing { osc.setMainVolume(draftVolume, force: true) }
                })
                .frame(minHeight: 44)
                .disabled(!osc.canAdjustVolume)
                .accessibilityLabel("Fader 1音量（Main）")
                .accessibilityValue(osc.volumeLabel)
                .accessibilityIdentifier("monitor.volume")
                HStack { Text("−∞"); Spacer(); Text("+6 dB") }
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text("MainとAN3/4の連動には、TotalMixのF1グループを使用します。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        }
        .onChange(of: osc.mainVolume) { _, value in
            if !dragging, let value { draftVolume = value }
        }
        .onChange(of: osc.connected) { _, connected in if !connected { dragging = false } }
        .onAppear { if let value = osc.mainVolume { draftVolume = value } }
    }

    private func toggle(_ title: String, icon: String, value: Bool?, pending: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.caption.weight(.semibold))
                Text(pending ? "確認中" : value.map { $0 ? "ON" : "OFF" } ?? "—")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(IOSPanelButtonStyle(selected: value == true))
        .disabled(!osc.connected || value == nil || pending)
        .accessibilityLabel(title)
        .accessibilityValue(pending ? "確認中" : value.map { $0 ? "ON" : "OFF" } ?? "未確認")
        .accessibilityIdentifier(id)
    }
}
