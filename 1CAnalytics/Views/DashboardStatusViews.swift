import SwiftUI

struct DashboardOfflineNotice: View {
    let date: Date?
    var isCached = false
    var errorMessage: String?
    var presentationRequest = 0
    @State private var isShowingOfflineDetails = false

    var body: some View {
        Group {
            if isShowingOfflineDetails, let errorMessage {
                offlineDetails(errorMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: isShowingOfflineDetails)
        .task(id: presentationTaskID) {
            guard errorMessage != nil else {
                isShowingOfflineDetails = false
                return
            }

            isShowingOfflineDetails = true
            try? await Task.sleep(for: .seconds(4))

            guard !Task.isCancelled else {
                return
            }
            isShowingOfflineDetails = false
        }
    }

    private var presentationTaskID: DashboardOfflineNoticeTaskID {
        DashboardOfflineNoticeTaskID(
            errorMessage: errorMessage,
            presentationRequest: presentationRequest
        )
    }

    private func offlineDetails(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isCached ? "icloud.slash.fill" : "externaldrive.badge.exclamationmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(isCached ? "Данные обновлены не полностью" : "Офлайн-кэш недоступен")
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isCached {
                    Text(cachedDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }

    private var cachedDateText: String {
        guard let date else {
            return "Дата последнего обновления неизвестна"
        }

        return "Последнее обновление: \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct DashboardOfflineNoticeTaskID: Equatable {
    let errorMessage: String?
    let presentationRequest: Int
}

struct DashboardConnectionStatus: View {
    let date: Date?
    var isCached = false
    var isRefreshing = false
    var hasError = false
    var onErrorTap: (() -> Void)?

    var body: some View {
        Group {
            if hasError, let onErrorTap {
                Button(action: onErrorTap) {
                    statusContent
                }
                .buttonStyle(.plain)
                .accessibilityHint("Показать подробности последней ошибки")
            } else {
                statusContent
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            statusIcon
                .fixedSize()

            statusText
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var statusText: some View {
        if isRefreshing {
            Text("Обновляем данные…")
        } else if hasError {
            ViewThatFits(in: .horizontal) {
                Text("Ошибка синхронизации · \(compactSynchronizationText)")
                    .fixedSize(horizontal: true, vertical: false)

                Text("Ошибка синхронизации")
                    .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                Text(lastSynchronizationText)
                    .fixedSize(horizontal: true, vertical: false)

                Text(compactSynchronizationText)
                    .fixedSize(horizontal: true, vertical: false)

                Text(compactSynchronizationText)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if hasError {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if isCached {
            Image(systemName: "icloud.slash.fill")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var accessibilityLabel: String {
        if isRefreshing {
            return "Обновление данных"
        }

        if hasError {
            return "Ошибка синхронизации. \(lastSynchronizationText)"
        }

        return isCached ? "Офлайн. \(lastSynchronizationText)" : lastSynchronizationText
    }

    private var lastSynchronizationText: String {
        guard let date else {
            return "Время последней синхронизации неизвестно"
        }

        return "Последняя синхронизация: \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var compactSynchronizationText: String {
        guard let date else {
            return "Синхронизация неизвестна"
        }

        return date.formatted(date: .numeric, time: .shortened)
    }
}

struct RefreshButton: View {
    let action: () async -> Void
    @State private var isRefreshing = false

    var body: some View {
        Button {
            Task {
                isRefreshing = true
                await action()
                isRefreshing = false
            }
        } label: {
            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
        }
        .disabled(isRefreshing)
        .accessibilityLabel("Обновить")
    }
}
