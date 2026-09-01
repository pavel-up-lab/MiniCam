import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        Group {
            if container.isReady {
                connectedPlaceholder
            } else {
                CameraSetupView(profile: container.profile)
            }
        }
        .background(Color(red: 0.035, green: 0.043, blue: 0.047))
    }

    private var connectedPlaceholder: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)

                Text("Камера подключена")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(archiveStatus)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private var archiveStatus: String {
        if container.archiveSegmentCount == 0 {
            return "Подключение работает, но за последние 36 часов записей не найдено"
        }

        return "Архив доступен: найдено фрагментов — \(container.archiveSegmentCount)"
    }
}
