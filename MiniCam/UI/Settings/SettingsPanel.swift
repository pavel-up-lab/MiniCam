import AppKit
import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.appFontScale) private var fontScale

    let onCancel: () -> Void
    let onSaved: () -> Void

    @State private var isMotionTrackingEnabled = true
    @State private var interfaceFontScale: InterfaceFontScale = .normal
    @State private var motionEventRecordingMode: MotionEventRecordingMode = .peopleAndVehicles
    @State private var motionEventRetention: MotionEventRetention = .threeDays
    @State private var externalFolderURL: URL?
    @State private var screenshotFolderURL: URL?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isClearConfirmationPresented = false

    private let accent = Color(red: 0.73, green: 0.95, blue: 0.18)
    private let panelBackground = Color(red: 0.055, green: 0.065, blue: 0.071)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                interfaceSection
                eventSettingsSection
                storageSection
                screenshotSection

                if let errorMessage {
                    Text(errorMessage)
                        .appFont(size: 11, weight: .medium)
                        .foregroundStyle(Color(red: 1.0, green: 0.47, blue: 0.39))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let successMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(successMessage)
                            .appFont(size: 11, weight: .semibold)
                    }
                    .foregroundStyle(accent)
                }

                actionRow
            }
            .padding(20)
        }
        .frame(width: panelWidth)
        .frame(maxHeight: 560)
        .foregroundStyle(.white)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.34), lineWidth: 1)
        }
        .overlay {
            if isClearConfirmationPresented {
                clearConfirmation
            }
        }
        .shadow(color: .black.opacity(0.62), radius: 30, y: 16)
        .onAppear(perform: loadDraft)
        .onDisappear {
            container.cancelInterfaceFontScalePreview()
        }
        .onExitCommand {
            guard !isSettingsBusy else { return }
            cancel()
        }
    }

    private var panelWidth: CGFloat {
        430 + ((fontScale - 1) * 140)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                Text("Настройки")
                    .appFont(size: 17, weight: .bold)
            }
                .foregroundStyle(accent)

            Spacer()

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white.opacity(0.72))
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSettingsBusy)
            .help("Закрыть без сохранения")
            .accessibilityLabel("Закрыть настройки без сохранения")
        }
    }

    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("ИНТЕРФЕЙС")
                .appFont(size: 10, weight: .bold, design: .monospaced)
                .foregroundStyle(.white.opacity(0.54))

            VStack(alignment: .leading, spacing: 8) {
                Text("Размер шрифта")
                    .appFont(size: 12, weight: .semibold)

                HStack(spacing: 4) {
                    ForEach(InterfaceFontScale.allCases, id: \.self) { scale in
                        Button {
                            interfaceFontScale = scale
                            container.previewInterfaceFontScale(scale)
                        } label: {
                            Text(scale.title)
                                .appFont(size: 11, weight: .bold)
                                .foregroundStyle(
                                    interfaceFontScale == scale
                                        ? Color(red: 0.06, green: 0.08, blue: 0.02)
                                        : Color.white.opacity(0.78)
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, max(8, 7 * fontScale))
                                .background(
                                    interfaceFontScale == scale
                                        ? accent
                                        : Color.white.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(
                                            interfaceFontScale == scale
                                                ? accent
                                                : Color.white.opacity(0.1),
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSettingsBusy)
                        .accessibilityLabel("Размер шрифта \(scale.title)")
                        .accessibilityAddTraits(
                            interfaceFontScale == scale ? .isSelected : []
                        )
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity)
                .background(
                    Color.black.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.2), lineWidth: 1)
                }
                .animation(.easeOut(duration: 0.14), value: interfaceFontScale)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var eventSettingsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("СОБЫТИЯ ДВИЖЕНИЯ")
                .appFont(size: 10, weight: .bold, design: .monospaced)
                .foregroundStyle(.white.opacity(0.54))

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Распознавать движение")
                        .appFont(size: 13, weight: .semibold)
                    Text("Только в новых данных архива")
                        .appFont(size: 10)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Toggle("", isOn: $isMotionTrackingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accent)
                    .disabled(isSettingsBusy)
            }

            Divider()
                .overlay(Color.white.opacity(0.09))

            settingsPickerRow(title: "Тип событий") {
                Picker("Тип событий", selection: $motionEventRecordingMode) {
                    ForEach(MotionEventRecordingMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                            .appFont(size: 11, weight: .medium)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: pickerWidth)
                .disabled(!isMotionTrackingEnabled || isSettingsBusy)
            }

            settingsPickerRow(title: "Хранить историю") {
                Picker("Срок хранения", selection: $motionEventRetention) {
                    ForEach(MotionEventRetention.allCases, id: \.self) { retention in
                        Text(retention.title).tag(retention)
                            .appFont(size: 11, weight: .medium)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: pickerWidth)
                .disabled(isSettingsBusy)
            }

            Divider()
                .overlay(Color.white.opacity(0.09))

            Button("Очистить всю историю…") {
                errorMessage = nil
                successMessage = nil
                isClearConfirmationPresented = true
            }
            .buttonStyle(SettingsDestructiveButtonStyle())
            .disabled(isSettingsBusy)
        }
        .padding(13)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func settingsPickerRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .appFont(size: 12, weight: .semibold)
            Spacer(minLength: 8)
            content()
        }
    }

    private var clearConfirmation: some View {
        ZStack {
            panelBackground.opacity(0.94)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "trash.fill")
                    Text("Очистить историю?")
                        .appFont(size: 15, weight: .bold)
                }
                    .foregroundStyle(Color(red: 1.0, green: 0.47, blue: 0.39))

                Text("Удалить все события движения и их кадры? Архив камеры, кадры перемотки и скриншоты останутся без изменений.")
                    .appFont(size: 12)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    Spacer()
                    Button("Отмена") {
                        isClearConfirmationPresented = false
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .disabled(isSettingsBusy)

                    Button(container.isClearingMotionEvents ? "Удаляем…" : "Удалить") {
                        clearHistory()
                    }
                    .buttonStyle(SettingsDestructiveButtonStyle())
                    .disabled(isSettingsBusy)
                }
            }
            .padding(18)
            .frame(width: 340 + ((fontScale - 1) * 150))
            .background(Color(red: 0.085, green: 0.095, blue: 0.102))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.72), radius: 24, y: 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ХРАНЕНИЕ КАДРОВ И СОБЫТИЙ")
                .appFont(size: 10, weight: .bold, design: .monospaced)
                .foregroundStyle(.white.opacity(0.54))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(externalFolderURL == nil ? "Внутренняя папка MiniCam" : "Внешняя папка")
                        .appFont(size: 12, weight: .semibold)

                    if let externalFolderURL {
                        Text(externalFolderURL.path)
                            .appFont(size: 10, design: .monospaced)
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                Button("Выбрать…", action: chooseFolder)
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .disabled(isSettingsBusy)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: storageSymbol)
                Text(storageDescription)
                    .appFont(size: 10, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
                .foregroundStyle(storageColor)

            if externalFolderURL != nil {
                Button("Вернуть внутреннюю папку") {
                    externalFolderURL = nil
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .appFont(size: 10, weight: .semibold)
                .foregroundStyle(.white.opacity(0.62))
                .disabled(isSettingsBusy)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            Spacer()

            Button("Вернуться", action: cancel)
                .buttonStyle(SettingsSecondaryButtonStyle())
                .disabled(isSettingsBusy)

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
            .disabled(isSettingsBusy)
        }
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("СКРИНШОТЫ")
                .appFont(size: 10, weight: .bold, design: .monospaced)
                .foregroundStyle(.white.opacity(0.54))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(screenshotFolderURL == nil ? "Рабочий стол" : "Выбранная папка")
                        .appFont(size: 12, weight: .semibold)

                    if let screenshotFolderURL {
                        Text(screenshotFolderURL.path)
                            .appFont(size: 10, design: .monospaced)
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                Button("Выбрать…", action: chooseScreenshotFolder)
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .disabled(isSettingsBusy)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: screenshotFolderSymbol)
                Text(screenshotFolderDescription)
                    .appFont(size: 10, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
                .foregroundStyle(screenshotFolderColor)

            if screenshotFolderURL != nil {
                Button("Вернуть Рабочий стол") {
                    screenshotFolderURL = nil
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .appFont(size: 10, weight: .semibold)
                .foregroundStyle(.white.opacity(0.62))
                .disabled(isSettingsBusy)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var screenshotFolderDescription: String {
        if container.isScreenshotFolderFallback, screenshotFolderURL != nil {
            return "Папка недоступна — временно используется Рабочий стол"
        }
        return screenshotFolderURL == nil
            ? "Скриншоты сохраняются на Рабочий стол"
            : "Папка для новых скриншотов выбрана"
    }

    private var screenshotFolderSymbol: String {
        container.isScreenshotFolderFallback && screenshotFolderURL != nil
            ? "exclamationmark.triangle.fill"
            : "checkmark.circle.fill"
    }

    private var screenshotFolderColor: Color {
        container.isScreenshotFolderFallback && screenshotFolderURL != nil
            ? .orange
            : accent
    }

    private var isSettingsBusy: Bool {
        container.isApplyingSettings || container.isClearingMotionEvents
    }

    private var pickerWidth: CGFloat {
        164 + ((fontScale - 1) * 80)
    }

    private func loadDraft() {
        interfaceFontScale = container.appSettings.interfaceFontScale
        isMotionTrackingEnabled = container.appSettings.isMotionTrackingEnabled
        motionEventRecordingMode = container.appSettings.motionEventRecordingMode
        motionEventRetention = container.appSettings.motionEventRetention
        externalFolderURL = container.currentExternalFolderURL
        screenshotFolderURL = container.currentCustomScreenshotFolderURL
        errorMessage = nil
        successMessage = nil
        isClearConfirmationPresented = false
    }

    private func cancel() {
        container.cancelInterfaceFontScalePreview()
        onCancel()
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
            successMessage = nil
        }
    }

    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку для скриншотов MiniCam"
        panel.prompt = "Выбрать"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            screenshotFolderURL = panel.url
            errorMessage = nil
            successMessage = nil
        }
    }

    private func clearHistory() {
        errorMessage = nil
        successMessage = nil
        Task {
            do {
                try await container.clearMotionEventHistory()
                isClearConfirmationPresented = false
                successMessage = "История очищена"
            } catch {
                isClearConfirmationPresented = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось полностью очистить историю событий."
            }
        }
    }

    private func save() {
        errorMessage = nil
        successMessage = nil
        Task {
            do {
                try await container.applySettings(
                    motionTrackingEnabled: isMotionTrackingEnabled,
                    interfaceFontScale: interfaceFontScale,
                    motionEventRecordingMode: motionEventRecordingMode,
                    motionEventRetention: motionEventRetention,
                    externalFolderURL: externalFolderURL,
                    screenshotFolderURL: screenshotFolderURL
                )
                onSaved()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось сохранить настройки."
            }
        }
    }
}

private struct SettingsDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appFontScale) private var fontScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 11, weight: .bold)
            .foregroundStyle(Color(red: 1.0, green: 0.52, blue: 0.46))
            .padding(.horizontal, 12)
            .frame(minHeight: max(30, 15 * fontScale + 12))
            .background(
                Color(red: 0.35, green: 0.12, blue: 0.11)
                    .opacity(configuration.isPressed ? 0.62 : 0.42)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(red: 0.75, green: 0.25, blue: 0.22).opacity(0.58), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appFontScale) private var fontScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 11, weight: .semibold)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.86))
            .padding(.horizontal, 12)
            .frame(minHeight: max(30, 15 * fontScale + 12))
            .background(Color.white.opacity(configuration.isPressed ? 0.05 : 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appFontScale) private var fontScale
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 11, weight: .bold)
            .foregroundStyle(Color(red: 0.06, green: 0.08, blue: 0.02))
            .padding(.horizontal, 14)
            .frame(minHeight: max(30, 15 * fontScale + 12))
            .background(accent.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
    }
}
