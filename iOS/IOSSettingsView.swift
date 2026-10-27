import SwiftUI
import Darwin

struct IOSSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var osc: OSCManager
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var sendPort = "7002"
    @State private var receivePort = "9002"
    @State private var enabled = true
    @State private var localAddresses: [String] = []
    @State private var showResetConfirmation = false
    private enum ConnectionField: Hashable { case host, sendPort, receivePort }
    @FocusState private var editingConnection: ConnectionField?

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                setupSection
                snapshotsSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }.accessibilityIdentifier("settings.done")
                }
            }
            .onAppear {
                host = settings.oscHost
                sendPort = String(settings.oscSendPort)
                receivePort = String(settings.oscReceivePort)
                enabled = settings.oscEnabled
                localAddresses = Self.wifiAddresses()
            }
            .confirmationDialog("Snapshotの表示名を初期値に戻しますか？", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                Button("表示名を初期値に戻す", role: .destructive) { settings.resetNames() }
            }
        }
    }

    private var connectionSection: some View {
        Section {
            Toggle("OSCを使用", isOn: $enabled).accessibilityIdentifier("oscEnabledToggle")
            VStack(alignment: .leading, spacing: 5) {
                Text("TotalMixを動かすMacのIPv4").font(.caption).foregroundStyle(.secondary)
                TextField("192.168.1.10", text: $host)
                    .keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editingConnection, equals: .host)
                    .accessibilityIdentifier("settings.host")
            }
            portField("送信先ポート", text: $sendPort, field: .sendPort, id: "settings.sendPort")
            portField("iPhoneの受信ポート", text: $receivePort, field: .receivePort, id: "settings.receivePort")
            Button("接続設定を適用・再接続") { applyConnection() }
                .disabled(enabled && !validConnection)
                .accessibilityIdentifier("settings.apply")
            if let error = osc.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("接続")
        } footer: {
            Text("MacとiPhoneを同じWi-Fi／LANに接続してください。IPv4アドレスと、異なる1024〜65535のポートを指定します。接続設定は「適用」で保存します。")
        }
    }

    private var setupSection: some View {
        Section {
            LabeledContent("このiPhoneのWi-Fi IPv4") {
                Text(localAddresses.isEmpty ? "Wi-Fi設定で確認" : localAddresses.joined(separator: "\n"))
                    .font(.callout.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("localIPAddress")
            }
            Text("TotalMix → Options → Enable OSC ControlをONにし、Mixer Settings → OSCで専用のController 2を設定します。")
            VStack(alignment: .leading, spacing: 8) {
                Text("① Controller 2：In UseをON")
                Text("② Port incoming：\(sendPort.isEmpty ? "7002" : sendPort)")
                Text("③ Remote Host：このiPhoneのWi-Fi IPv4")
                Text("④ Port outgoing：\(receivePort.isEmpty ? "9002" : receivePort)")
                Text("⑤ Compatibility：TotalMix 1.90／1.96の従来OSCモード")
            }
            .font(.subheadline)
            Text("M1の対象はMute Group 1に、Main（AN1/2）とAN3/4は有効なFader Group 1に登録してください。")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("TotalMix側の設定")
        } footer: {
            Text("Mac版と併用する場合は、別のControllerとポートを使用します。応答待ちのときは、iOSの「設定」でこのアプリのローカルネットワークアクセス、Macのファイアウォール、両端のアドレスを確認してください。アプリを離れると切断し、戻ると現在の状態を取得します。")
        }
    }

    private var snapshotsSection: some View {
        Section {
            ForEach(SnapshotCommand.numbers, id: \.self) { number in
                VStack(alignment: .leading, spacing: 8) {
                    Text("SNAPSHOT \(number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    TextField("Snapshot \(number)", text: Binding(
                        get: { settings.snapshotNames[number - 1] },
                        set: { settings.setName($0, for: number) }
                    ))
                    .accessibilityLabel("Snapshot \(number)の表示名")
                    .accessibilityIdentifier("settings.name.\(number)")
                    Toggle("HIDE（非表示）", isOn: Binding(
                        get: { settings.hiddenSnapshots.contains(number) },
                        set: { settings.setHidden($0, for: number) }
                    ))
                    .accessibilityLabel("Snapshot \(number)を非表示")
                    .accessibilityIdentifier("settings.hide.\(number)")
                }
                .padding(.vertical, 4)
            }
            Button("表示名を初期値に戻す", role: .destructive) { showResetConfirmation = true }
        } header: {
            Text("Snapshotの表示名・HIDE")
        } footer: {
            Text("表示名とHIDEは変更すると自動保存されます。TotalMix側の名前や保存内容は変更しません。")
        }
    }

    private func portField(_ label: String, text: Binding<String>, field: ConnectionField, id: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            TextField("", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(minWidth: 65, maxWidth: 110).focused($editingConnection, equals: field)
                .accessibilityLabel(label).accessibilityIdentifier(id)
        }
    }

    private var validConnection: Bool {
        var address = in_addr()
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inet_pton(AF_INET, trimmed, &address) == 1,
              let send = Int(sendPort), let receive = Int(receivePort),
              (1024...65535).contains(send), (1024...65535).contains(receive), send != receive else { return false }
        let first = address.s_addr.bigEndian >> 24
        return first > 0 && first < 224 && trimmed != "255.255.255.255"
    }

    private func applyConnection() {
        editingConnection = nil
        guard !enabled || validConnection else { return }
        settings.oscEnabled = enabled
        // A disabled connection can be saved without replacing its last valid endpoint.
        if validConnection, let send = Int(sendPort), let receive = Int(receivePort) {
            settings.oscHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.oscSendPort = send
            settings.oscReceivePort = receive
        }
        osc.reconnect()
    }

    private static func wifiAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let node = cursor {
            let item = node.pointee
            defer { cursor = item.ifa_next }
            guard String(cString: item.ifa_name) == "en0", let address = item.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }
}
