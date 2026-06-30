import SwiftUI

@main
struct OneCAnalyticsApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: DashboardViewModel(provider: AnalyticsProviderFactory.makeProvider()))
        }
    }
}
