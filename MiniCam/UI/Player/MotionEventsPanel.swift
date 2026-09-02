import SwiftUI

struct MotionEventsPanel: View {
    @ObservedObject var analyzer: ArchiveMotionAnalyzer
    @Binding var isExpanded: Bool
    let unreadCount: Int
    let onSelect: (MotionEvent) -> Void

    private let accent = Color(red: 0.73, green: 0.95, blue: 0.18)

    var body: some View {
        Group {
            if isExpanded {
                expandedPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                collapsedTab
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(-8)
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .help("Свернуть события")

                VStack(alignment: .leading, spacing: 2) {
                    Text("ДВИЖЕНИЕ")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text(analyzer.isAnalyzing ? "анализ нового архива" : "люди и транспорт")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                if analyzer.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.12))

            if analyzer.events.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(analyzer.events) { event in
                            Button {
                                onSelect(event)
                            } label: {
                                MotionEventCard(
                                    event: event,
                                    imageURL: analyzer.imageURL(for: event)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Перейти к началу движения")
                        }
                    }
                    .padding(12)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: 320)
        .background(.black.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 16, x: -4, y: 4)
    }

    private var collapsedTab: some View {
        Button {
            isExpanded = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))

                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .semibold))

                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(accent, in: Capsule())
                }
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 12)
            .background(.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent.opacity(0.65))
                    .frame(width: 2)
            }
        }
        .buttonStyle(.plain)
        .help("Открыть события движения")
        .accessibilityLabel("Открыть события движения")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "figure.walk")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(accent.opacity(0.8))
            Text("СОБЫТИЙ ПОКА НЕТ")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text("Появятся только начала движения\nв новых фрагментах архива")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct MotionEventCard: View {
    let event: MotionEvent
    let imageURL: URL

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white.opacity(0.06)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(height: 154)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                Text(event.categories.map(\.title).joined(separator: " · "))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
            }

            Text(event.startedAt.formatted(date: .abbreviated, time: .standard))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(9)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .task(id: event.id) {
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: imageURL)
            }.value
            if let data {
                image = NSImage(data: data)
            }
        }
    }
}
