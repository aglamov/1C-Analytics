import SwiftUI

@main
struct OneCAnalyticsApp: App {
    @StateObject private var authenticationViewModel = AuthenticationViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if authenticationViewModel.state == .signedIn {
                    DashboardView(
                        viewModel: DashboardViewModel(provider: AnalyticsProviderFactory.makeProvider()),
                        onSignOut: authenticationViewModel.signOut
                    )
                } else {
                    AuthenticationView(viewModel: authenticationViewModel)
                }
            }
        }
    }
}
