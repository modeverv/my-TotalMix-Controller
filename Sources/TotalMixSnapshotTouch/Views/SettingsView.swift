import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
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
                Section("接続（すべての操作にOSCを使用）") {
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

            }.formStyle(.grouped)
        }
        .frame(width: 580, height: 680)
        .preferredColorScheme(.dark)
    }
}
