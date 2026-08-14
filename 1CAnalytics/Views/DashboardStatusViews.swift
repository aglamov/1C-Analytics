import SwiftUI

enum DashboardSynchronizationItemPresentationPolicy {
    static func isInitiallyExpanded(
        for kind: DashboardSynchronizationSession.Item.Kind
    ) -> Bool {
        switch kind {
        case .standard, .extended:
            false
        }
    }
}

struct DashboardSynchronizationIndicator: View {
    let session: DashboardSynchronizationSession
    let isCached: Bool
    let hasCacheError: Bool
    let action: () -> Void
    @State private var showsCompletionPill = true

    var body: some View {
        Button(action: action) {
            Group {
                if session.phase == .running || showsCompletionPill {
                    HStack(spacing: 9) {
                        statusIcon
                        Text("Обновлено \(session.completedCount) из \(session.totalCount)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                } else {
                    statusIcon
                        .font(.headline.weight(.bold))
                        .frame(width: 48, height: 48)
                }
            }
            .foregroundStyle(.primary)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.secondary.opacity(0.15), lineWidth: 1) }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Показать подробности синхронизации")
        .task(id: session.id) {
            showsCompletionPill = true
        }
        .task(id: session.phase) {
            guard session.phase == .completed else {
                showsCompletionPill = true
                return
            }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { showsCompletionPill = false }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if session.phase == .running {
            ProgressView().controlSize(.small).accessibilityHidden(true)
        } else if hasCacheError || session.items.contains(where: { $0.status == .failed }) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else if isCached || session.hasFailures {
            Image(systemName: "icloud.slash.fill").foregroundStyle(.orange)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private var accessibilityLabel: String {
        let phase = session.phase == .running ? "Обновление выполняется" : "Обновление завершено"
        return "\(phase). Обновлено \(session.completedCount) из \(session.totalCount)"
    }
}

struct DashboardSynchronizationDetailsView: View {
    let session: DashboardSynchronizationSession
    let networkError: String?
    let cacheError: String?

    var body: some View {
        NavigationStack {
            List {
                if networkError != nil || cacheError != nil {
                    Section("Ошибки текущей сессии") {
                        if let networkError {
                            Label(networkError, systemImage: "network.slash")
                                .foregroundStyle(.orange)
                        }
                        if let cacheError {
                            Label(cacheError, systemImage: "externaldrive.badge.exclamationmark")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    ForEach(session.items) { item in
                        DashboardSynchronizationItemRow(item: item)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .textCase(nil)
                    }
                } footer: {
                    Text(sessionSummary)
                        .textCase(nil)
                }
            }
            .navigationTitle("Текущий сеанс обновления")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sessionSummary: String {
        let progress = "Завершено \(session.completedCount) из \(session.totalCount)"
        guard let completedAt = session.completedAt else { return progress }
        return "\(progress) · \(completedAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct DashboardSynchronizationItemRow: View {
    let item: DashboardSynchronizationSession.Item
    @State private var isExpanded: Bool

    init(item: DashboardSynchronizationSession.Item) {
        self.item = item
        _isExpanded = State(
            initialValue: DashboardSynchronizationItemPresentationPolicy.isInitiallyExpanded(
                for: item.kind
            )
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if item.charts.isEmpty {
                Text(item.status == .failed ? "Список графиков не был получен" : "В разделе нет графиков")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(item.charts) { chart in
                    chartRow(chart)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                statusImage(item.status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.subheadline.weight(.semibold))
                    Text(itemStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = item.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .accessibilityHint(item.charts.isEmpty ? "" : "Показать состояние всех графиков раздела")
    }

    private var itemStatusText: String {
        var components = [statusTitle(item.status)]
        if !item.charts.isEmpty {
            components.append(graphCountText(item.charts.count))
        }
        if let timestamp = item.timestamp {
            components.append(DashboardSynchronizationTextPolicy.timestamp(for: timestamp))
        }
        return components.joined(separator: " · ")
    }

    private func chartRow(_ chart: DashboardSynchronizationSession.Item.Chart) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusImage(chart.status, compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(chart.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(chartMetadata(chart))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let source = chart.source, !source.isEmpty {
                    Text("Источник: \(source)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error = chart.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func chartMetadata(_ chart: DashboardSynchronizationSession.Item.Chart) -> String {
        var components = [statusTitle(chart.status), chart.type]
        if chart.valueCount > 0 {
            components.append(valueCountText(chart.valueCount))
        }
        return components.joined(separator: " · ")
    }

    private func statusImage(
        _ status: DashboardSynchronizationSession.Item.Status,
        compact: Bool = false
    ) -> some View {
        Image(systemName: statusSymbol(status))
            .font(compact ? .caption : .body)
            .foregroundStyle(statusColor(status))
            .frame(width: compact ? 18 : 22)
            .accessibilityHidden(true)
    }

    private func statusTitle(_ status: DashboardSynchronizationSession.Item.Status) -> String {
        switch status {
        case .pending: "Ожидание"
        case .updating: "Обновляется"
        case .succeeded: "Обновлён"
        case .cached: "Из базы"
        case .failed: "Ошибка"
        }
    }

    private func statusSymbol(_ status: DashboardSynchronizationSession.Item.Status) -> String {
        switch status {
        case .pending: "clock"
        case .updating: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .cached: "externaldrive.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: DashboardSynchronizationSession.Item.Status) -> Color {
        switch status {
        case .pending: .secondary
        case .updating: .blue
        case .succeeded: .green
        case .cached: .orange
        case .failed: .red
        }
    }

    private func graphCountText(_ count: Int) -> String {
        "\(count) \(russianPlural(count, one: "график", few: "графика", many: "графиков"))"
    }

    private func valueCountText(_ count: Int) -> String {
        "\(count) \(russianPlural(count, one: "значение", few: "значения", many: "значений"))"
    }

    private func russianPlural(_ value: Int, one: String, few: String, many: String) -> String {
        let remainder100 = value % 100
        if 11...14 ~= remainder100 { return many }
        switch value % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}

struct DashboardSectionVisualStyle {
    let symbol: String
    let tint: Color

    static func style(for title: String) -> Self {
        switch AnalyticsAPIContract.normalize(title) {
        case AnalyticsAPIContract.normalize("Образование"):
            Self(symbol: "graduationcap.fill", tint: .cyan)
        case AnalyticsAPIContract.normalize("Финансы"):
            Self(symbol: "rublesign", tint: .mint)
        case AnalyticsAPIContract.normalize("Наука"):
            Self(symbol: "flask.fill", tint: .orange)
        case AnalyticsAPIContract.normalize("Приемная кампания"):
            Self(symbol: "person.crop.circle.badge.checkmark", tint: .purple)
        case AnalyticsAPIContract.normalize("Международная деятельность"):
            Self(symbol: "globe.europe.africa.fill", tint: .pink)
        case AnalyticsAPIContract.normalize("Кадры"):
            Self(symbol: "person.text.rectangle.fill", tint: .blue)
        default:
            Self(symbol: "square.grid.2x2.fill", tint: .gray)
        }
    }
}

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
                .layoutPriority(1)

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
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusText: some View {
        if isRefreshing {
            Text("Обновляем данные…")
        } else if hasError {
            Text("Ошибка · \(compactSynchronizationText)")
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
        } else {
            Text("Синхронизация · \(compactSynchronizationText)")
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
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

        return "Последняя синхронизация: \(DashboardSynchronizationTextPolicy.timestamp(for: date))"
    }

    private var compactSynchronizationText: String {
        guard let date else {
            return "Синхронизация неизвестна"
        }

        return DashboardSynchronizationTextPolicy.timestamp(for: date)
    }
}

enum DashboardSynchronizationTextPolicy {
    static func timestamp(
        for date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd.MM.yy, HH:mm"
        return formatter.string(from: date)
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
