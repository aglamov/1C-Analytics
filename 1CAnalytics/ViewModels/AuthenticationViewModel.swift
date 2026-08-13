import Foundation

@MainActor
final class AuthenticationViewModel: ObservableObject {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
    }

    @Published private(set) var state: State

    private let authenticationService: RUDNAuthenticationService
    private let credentialsStore: any AuthenticationCredentialsStoring
    private let dashboardCache: any DashboardCaching

    init(
        authenticationService: RUDNAuthenticationService = RUDNAuthenticationService(),
        credentialsStore: any AuthenticationCredentialsStoring = AuthenticationCredentialsStore.shared,
        dashboardCache: any DashboardCaching = DashboardCacheFactory.makeCache()
    ) {
        self.authenticationService = authenticationService
        self.credentialsStore = credentialsStore
        self.dashboardCache = dashboardCache
        self.state = (try? credentialsStore.load()) != nil ? .signedIn : .signedOut
    }

    func signIn() async {
        state = .signingIn

        do {
            try await authenticationService.signIn()
            state = .signedIn
        } catch AuthenticationError.cancelled {
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        var signOutError: Error?

        do {
            try dashboardCache.clearDashboard()
        } catch {
            signOutError = error
        }

        do {
            try credentialsStore.clear()
        } catch {
            signOutError = signOutError ?? error
        }

        if let signOutError {
            state = .failed(signOutError.localizedDescription)
        } else {
            state = .signedOut
        }
    }

    func handleSessionExpired() {
        signOut()
    }
}
