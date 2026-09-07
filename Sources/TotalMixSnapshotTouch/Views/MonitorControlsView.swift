import SwiftUI

struct MonitorControlsView: View {
    @EnvironmentObject private var osc: OSCManager
    @EnvironmentObject private var settings: AppSettings
    @State private var dragging = false
    @State private var draftVolume = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { switches; fader.frame(minWidth: 220) }
                VStack(spacing: 12) { switches; fader }
            }
            HStack(spacing: 6) {
                Circle().fill(osc.connected ? Color.mint : Color.orange).frame(width: 6, height: 6)
                Text(osc.errorMessage ?? (osc.connected ? "OSC同期中 · Fader 1: Main（AN1/2）＋ AN3/4" : (settings.oscEnabled ? "OSC応答待ち — 設定を確認してください" : "OSCは無効です")))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: osc.mainVolume) { value in
            if !dragging, let value { draftVolume = value }
        }
        .onAppear { if let value = osc.mainVolume { draftVolume = value } }
        .onChange(of: osc.connected) { connected in if !connected { dragging = false } }
    }
    private var switches: some View {
        HStack(spacing: 10) {
            control("M1 MUTE", icon: "speaker.slash.fill", value: osc.muteGroup1, pending: osc.pendingMute, action: osc.toggleMuteGroup1)
            control("DIM", icon: "speaker.wave.1.fill", value: osc.dim, pending: osc.pendingDim, action: osc.toggleDim)
            Button { osc.setMainVolumeToZeroDB() } label: {
                VStack(spacing: 6) {
                    Text("Fader 1").font(.system(size: 14, weight: .semibold))
                    Text("0 dB").font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                .frame(minWidth: 80, minHeight: 60)
                .padding(.horizontal, 8)
                .background(Color.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.mint.opacity(0.4)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!osc.canAdjustVolume)
            .accessibilityLabel("Fader 1を0 dBに設定")
            .help("Mainを0 dBに設定します。Fader 1内の音量差は維持されます。")
        }
    }
    private func control(_ name: String, icon: String, value: Bool?, pending: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Label(name, systemImage: icon).font(.system(size: 14, weight: .semibold))
                Text(pending ? "確認中" : value.map { $0 ? "ON" : "OFF" } ?? "—")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .frame(minWidth: 95, minHeight: 60)
            .padding(.horizontal, 8)
            .background(value == true ? Color.orange.opacity(0.25) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(value == true ? Color.orange : Color.white.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!osc.connected || value == nil || pending)
        .accessibilityLabel(name)
        .accessibilityValue(pending ? "確認中" : value.map { $0 ? "ON" : "OFF" } ?? "未接続")
    }
    private var fader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Fader 1 VOLUME").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(osc.volumeLabel).font(.system(size: 16, weight: .medium, design: .monospaced))
            }
            Slider(value: Binding(
                get: { dragging ? draftVolume : osc.mainVolume ?? draftVolume },
                set: { draftVolume = $0; osc.setMainVolume($0) }
            ), in: 0...1, onEditingChanged: { editing in
                dragging = editing
                if !editing { osc.setMainVolume(draftVolume, force: true) }
            })
            .controlSize(.large)
            .frame(minHeight: 36)
            .tint(.mint)
            .disabled(!osc.canAdjustVolume)
            .accessibilityLabel("Fader 1音量（Main）")
            .accessibilityValue(osc.volumeLabel)
            HStack { Text("−∞"); Spacer(); Text("+6 dB") }
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
