import SwiftUI

struct SnapshotButton: View {
    let number: Int
    let name: String
    let isSelected: Bool
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(format: "%02d", number))
                        .font(.system(size: 38, weight: .light, design: .rounded))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2).foregroundStyle(Color.mint)
                    }
                }
                Spacer(minLength: 0)
                Text(name)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.55)
                Text(isSelected ? "選択中" : "SNAPSHOT \(number)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.mint : Color.secondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(SnapshotButtonStyle(isSelected: isSelected))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("Snapshot \(number)、\(name)")
        .accessibilityValue(isSelected ? "選択中" : "")
        .help("Snapshot \(number)を呼び出す（キー \(number)）")
    }
}

private struct SnapshotButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.mint.opacity(0.32) : (isSelected ? Color.mint.opacity(0.13) : Color.white.opacity(0.055)))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isSelected ? Color.mint : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
