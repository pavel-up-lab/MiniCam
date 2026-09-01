import SwiftUI

struct CameraSetupView: View {
    @EnvironmentObject private var container: AppContainer

    @State private var host: String
    @State private var httpPort: String
    @State private var rtspPort: String
    @State private var channel: String
    @State private var username = "admin"
    @State private var password = ""
    @State private var validationMessage: String?

    init(profile: CameraProfile) {
        _host = State(initialValue: profile.host)
        _httpPort = State(initialValue: String(profile.httpPort))
        _rtspPort = State(initialValue: String(profile.rtspPort))
        _channel = State(initialValue: String(profile.channel))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.043, blue: 0.047),
                    Color(red: 0.075, green: 0.086, blue: 0.088)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                identityPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                setupPanel
                    .frame(width: 390)
                    .padding(34)
            }
        }
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 72, height: 72)

                Image(systemName: "video.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(accent)
            }

            Text("MiniCam")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Прямой эфир и архив камеры\nна одной временной шкале.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.62))
                .lineSpacing(5)

            HStack(spacing: 8) {
                statusDot
                Text("ЛОКАЛЬНО · БЕЗ ОБЛАКА")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.48))
            }
            .padding(.top, 12)

            Spacer()
        }
        .padding(54)
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Подключение")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Данные сохраняются только на этом Mac.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.48))
            }

            VStack(spacing: 13) {
                field("Адрес камеры", text: $host)

                HStack(spacing: 12) {
                    field("HTTP", text: $httpPort)
                    field("RTSP", text: $rtspPort)
                    field("Канал", text: $channel)
                }

                field("Пользователь", text: $username)

                SecureField("Пароль", text: $password)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(fieldBackground)
                    .foregroundColor(.white)
            }

            if let message = visibleMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.47, blue: 0.39))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: connect) {
                HStack(spacing: 9) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.black.opacity(0.75))
                    } else {
                        Image(systemName: "arrow.right")
                    }

                    Text(isChecking ? "Проверяю камеру…" : "Подключить камеру")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundColor(Color.black.opacity(0.82))
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .disabled(isChecking)

            Spacer()

            Text("Hikvision · RTSP + ISAPI")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var visibleMessage: String? {
        if let validationMessage {
            return validationMessage
        }
        if case let .failed(message) = container.connectionState {
            return message
        }
        return nil
    }

    private var isChecking: Bool {
        container.connectionState == .checking
    }

    private var accent: Color {
        Color(red: 0.72, green: 0.94, blue: 0.48)
    }

    private var statusDot: some View {
        Circle()
            .fill(accent)
            .frame(width: 7, height: 7)
            .shadow(color: accent.opacity(0.65), radius: 7)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.075))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            )
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(fieldBackground)
            .foregroundColor(.white)
    }

    private func connect() {
        guard
            let parsedHTTPPort = UInt16(httpPort),
            let parsedRTSPPort = UInt16(rtspPort),
            let parsedChannel = UInt8(channel),
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            validationMessage = "Проверьте адрес, порты и номер канала."
            return
        }

        validationMessage = nil
        let profile = CameraProfile(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            httpPort: parsedHTTPPort,
            rtspPort: parsedRTSPPort,
            channel: parsedChannel
        )
        let credentials = CameraCredentials(username: username, password: password)

        Task {
            await container.connect(profile: profile, credentials: credentials)
        }
    }
}

