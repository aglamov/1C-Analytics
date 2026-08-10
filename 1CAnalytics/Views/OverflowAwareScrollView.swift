import SwiftUI

struct OverflowAwareScrollView<Content: View>: View {
    let content: Content
    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var contentBottom: CGFloat = 0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var hasOverflow: Bool {
        contentHeight > viewportHeight + 1
    }

    private var showsMoreBelow: Bool {
        hasOverflow && contentBottom > viewportHeight + 8
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: DetailContentHeightKey.self, value: proxy.size.height)
                            .preference(
                                key: DetailContentBottomKey.self,
                                value: proxy.frame(in: .named("detail-scroll")).maxY
                            )
                    }
                }
                .padding(.bottom, hasOverflow ? 38 : 0)
        }
        .coordinateSpace(name: "detail-scroll")
        .scrollBounceBehavior(.basedOnSize)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: DetailViewportHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(DetailContentHeightKey.self) { scheduleContentHeightUpdate($0) }
        .onPreferenceChange(DetailContentBottomKey.self) { scheduleContentBottomUpdate($0) }
        .onPreferenceChange(DetailViewportHeightKey.self) { scheduleViewportHeightUpdate($0) }
        .overlay(alignment: .bottom) {
            if showsMoreBelow {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, Color(.systemGroupedBackground).opacity(0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)

                    Label("Прокрутите, чтобы увидеть ещё", systemImage: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 6)
                        .background(Color(.systemGroupedBackground).opacity(0.94))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsMoreBelow)
    }

    private func scheduleContentHeightUpdate(_ value: CGFloat) {
        guard value.isFinite else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard abs(contentHeight - value) >= 1 else {
                return
            }
            contentHeight = value
        }
    }

    private func scheduleContentBottomUpdate(_ value: CGFloat) {
        guard value.isFinite else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard abs(contentBottom - value) >= 1 else {
                return
            }
            contentBottom = value
        }
    }

    private func scheduleViewportHeightUpdate(_ value: CGFloat) {
        guard value.isFinite else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard abs(viewportHeight - value) >= 1 else {
                return
            }
            viewportHeight = value
        }
    }
}

private struct DetailContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DetailViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DetailContentBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
