import AppKit
import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var container: AppContainer

    let onCancel: () -> Void
    let onSaved: () -> Void

    @State private var isMotionTrackingEnabled = true
    @State private var externalFolderURL: URL?
    @State private var errorMessage: String?

    private let accent = Color(red: 0.73, green: 0.95, blue: 0.18)
    private let panelBackground = Color(red: 0.055, green: 0.065, blue: 0.071)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            trackingRow
            storageSection

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.47, blue: 0.39))
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow
        }
        .padding(20)
        .frame(width: 430)
        .foregroundStyle(.white)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.62), radius: 30, y: 16)
        .onAppear(perform: loadDraft)
        .onExitCommand {
            guard !container.isApplyingSettings else { return }
            onCancel()
        }
    }

    private var header: some View {
        HStack {
            Label("Настройки", systemImage: "gearshape.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accent)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white.opacity(0.72))
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(container.isApplyingSettings)
            .help("Закрыть без сохранения")
            .accessibilityLabel("Закрыть настройки без сохранения")
        }
    }

    private var trackingRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Распознавать движение")
                    .font(.system(size: 13, weight: .semibold))
                Text("Люди и транспорт в новых данных архива")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: $isMotionTrackingEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .disabled(container.isApplyingSettings)
        }
        .padding(13)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ХРАНЕНИЕ КАДРОВ И СОБЫТИЙ")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.54))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(externalFolderURL == nil ? "Внутренняя папка MiniCam" : "Внешняя папка")
                        .font(.system(size: 12, weight: .semibold))

                    if let externalFolderURL {
                        Text(externalFolderURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                Button("Выбрать…", action: chooseFolder)
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .disabled(container.isApplyingSettings)
            }

            Label(storageDescription, systemImage: storageSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(storageColor)

            if externalFolderURL != nil {
                Button("Вернуть внутреннюю папку") {
                    externalFolderURL = nil
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .disabled(container.isApplyingSettings)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            Spacer()

            Button("Отмена", action: onCancel)
                .buttonStyle(SettingsSecondaryButtonStyle())
                .disabled(container.isApplyingSettings)

            Button {
                save()
            } label: {
                HStack(spacing: 7) {
                    if container.isApplyingSettings {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                    }
                    Text(container.isApplyingSettings ? "Переносим…" : "Сохранить")
                }
            }
            .buttonStyle(SettingsPrimaryButtonStyle(accent: accent))
            .keyboardShortcut(.defaultAction)
            .disabled(container.isApplyingSettings)
        }
    }

    private var storageDescription: String {
        if container.isApplyingSettings { return "Переносим данные…" }
        switch container.storageStatus {
        case .internalStorage:
            return "Используется внутренняя папка"
        case .externalStorage:
            return "Внешняя папка доступна"
        case .internalFallback:
            return "Внешняя папка недоступна — временно используется внутренняя"
        case let .retryPending(_, message):
            return message
        }
    }

    private var storageSymbol: String {
        container.storageStatus.requiresAttention
            ? "exclamationmark.triangle.fill"
            : "checkmark.circle.fill"
    }

    private var storageColor: Color {
        container.storageStatus.requiresAttention ? .orange : accent
    }

    private func loadDraft() {
        isMotionTrackingEnabled = container.appSettings.isMotionTrackingEnabled
        externalFolderURL = container.currentExternalFolderURL
        errorMessage = nil
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку для данных MiniCam"
        panel.prompt = "Выбрать"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            externalFolderURL = panel.url
            errorMessage = nil
        }
    }

    private func save() {
        errorMessage = nil
        Task {
            do {
                try await container.applySettings(
                    motionTrackingEnabled: isMotionTrackingEnabled,
                    externalFolderURL: externalFolderURL
                )
                onSaved()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось сохранить настройки."
            }
        }
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.86))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.white.opacity(configuration.isPressed ? 0.05 : 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(red: 0.06, green: 0.08, blue: 0.02))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(accent.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
    }
}
