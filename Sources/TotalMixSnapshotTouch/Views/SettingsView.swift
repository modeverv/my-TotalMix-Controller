import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var midi: MIDIManager
    @EnvironmentObject private var osc: OSCManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("設定").font(.title2.bold())
                Spacer()
                Button("完了") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(24)
            Form {
                Section("MIDI出力先") {
                    Picker("Destination", selection: Binding<UInt32>(
                        get: { midi.selectedDestination?.endpoint ?? 0 },
                        set: { endpoint in
                            if let destination = midi.destinations.first(where: { $0.endpoint == endpoint }) { midi.selectDestination(destination) }
                        }
                    )) {
                        Text("未接続 / 出力先を選択").tag(UInt32(0))
                        ForEach(midi.destinations) { destination in
                            Text(destination.displayName).tag(destination.endpoint)
                        }
                    }
                    Button("MIDI出力先を再検索", systemImage: "arrow.clockwise") { midi.refreshDestinations() }
                    Picker("送信方式", selection: $settings.encoding) {
                        ForEach(SnapshotCommand.Encoding.allCases) { encoding in Text(encoding.title).tag(encoding) }
                    }
                    Text("通常はNote Offを使用します。反応しない場合のみ互換方式を試してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("M1・F1・Dim（OSC）") {
                    Toggle("OSCを使用", isOn: $settings.oscEnabled)
                        .onChange(of: settings.oscEnabled) { _ in osc.reconnect() }
                    TextField("TotalMixのIncomingポート", value: $settings.oscSendPort, format: .number.grouping(.never))
                    TextField("このアプリの受信ポート", value: $settings.oscReceivePort, format: .number.grouping(.never))
                    Button("ポート設定を適用・再接続") { osc.reconnect() }
                    Text("TotalMix: Enable OSC ControlをON。OSC ControllerをIn Use、Incoming=7001、Outgoing=9001、Remote Host=127.0.0.1に設定してください。従来のOSCモードを使用します。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("F1はMain（AN1/2）とAN3/4を登録・有効化してください。フェーダーはMainを動かし、TotalMixのF1連動を使用します。Dimの減衰量はTotalMix側の設定です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Snapshotの表示名・HIDE") {
                    ForEach(SnapshotCommand.numbers, id: \.self) { number in
                        HStack {
                            TextField("Snapshot \(number)", text: Binding(
                                get: { settings.snapshotNames[number - 1] },
                                set: { settings.setName($0, for: number) }
                            ))
                            Toggle("HIDE", isOn: Binding(
                                get: { settings.hiddenSnapshots.contains(number) },
                                set: { settings.setHidden($0, for: number) }
                            ))
                            .toggleStyle(.checkbox)
                            .fixedSize()
                            .accessibilityLabel("Snapshot \(number)を非表示")
                        }
                    }
                    Button("表示名を初期値に戻す") { settings.resetNames() }
                    Text("HIDEをオンにするとボタンと数字キー操作を無効にします。変更は自動保存され、オフにすると再表示できます。TotalMix側のSnapshotは変更しません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("TotalMix側の設定") {
                    Text("Enable MIDI Control: ON\nIn Use: ON / Input: IAC TotalMixRemote\nEnable Protocol Support: ON\nDisable MIDI in background: OFF\nOutput Port: None")
                        .font(.caption).textSelection(.enabled)
                }
            }.formStyle(.grouped)
        }
        .frame(width: 580, height: 680)
        .preferredColorScheme(.dark)
    }
}
