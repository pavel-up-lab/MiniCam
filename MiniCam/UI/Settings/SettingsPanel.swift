import AppKit
import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var isPresented: Bool

    @State private var isMotionTrackingEnabled = true
    @State private var externalFolderURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Настройки")
                .font(.system(size: 18, weight: .semibold))

            Toggle("Распознавать движение", isOn: $isMotionTrackingEnabled)

            VStack(alignment: .leading, spacing: 8) {
                Text("Хранение кадров и событий")
                    .font(.system(size: 13, weight: .semibold))

                Text(folderDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Выбрать…", action: chooseFolder)

                    if externalFolderURL != nil {
                        Button("Вернуть внутреннюю папку") {
                            externalFolderURL = nil
                            errorMessage = nil
                        }
                    }
                }

                Label(storageDescription, systemImage: storageSymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(storageColor)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Отмена") {
                    isPresented = false
                }
                Button("Сохранить") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(container.isApplyingSettings)
            }
        }
        .padding(20)
        .frame(width: 430)
        .onAppear(perform: loadDraft)
    }

    private var folderDescription: String {
        externalFolderURL?.path ?? "Внутренняя папка MiniCam"
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
        container.storageStatus.requiresAttention ? .orange : .secondary
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
                isPresented = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось сохранить настройки."
            }
        }
    }
}
