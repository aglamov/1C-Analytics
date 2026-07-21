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
    private let credentialsStore: AuthenticationCredentialsStore

    init(
        authenticationService: RUDNAuthenticationService = RUDNAuthenticationService(),
        credentialsStore: AuthenticationCredentialsStore = .shared
    ) {
        self.authenticationService = authenticationService
        self.credentialsStore = credentialsStore
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
        do {
            try credentialsStore.clear()
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
