import Foundation
import Security
import UIKit
import WebKit

enum AuthenticationError: LocalizedError {
    case cancelled
    case invalidConfiguration
    case missingAuthorizationCode
    case missingCredentials
    case invalidBackendResponse
    case invalidState
    case backendRejected(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Вход отменён."
        case .invalidConfiguration:
            "Не удалось сформировать адрес входа."
        case .missingAuthorizationCode:
            "RUDN ID не вернул код авторизации."
        case .missingCredentials:
            "Данные сессии не найдены. Выполните вход повторно."
        case .invalidBackendResponse:
            "Сервер авторизации вернул некорректный ответ."
        case .invalidState:
            "Не удалось подтвердить безопасность ответа авторизации. Повторите вход."
        case let .backendRejected(statusCode, message):
            if let message, !message.isEmpty {
                "Сервер не подтвердил авторизацию (код \(statusCode)): \(message)"
            } else {
                "Сервер не подтвердил авторизацию (код \(statusCode))."
            }
        }
    }
}

@MainActor
final class RUDNAuthenticationService {
    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let credentialsStore: AuthenticationCredentialsStore

    init(
        configuration: AppConfiguration = .load(),
        urlSession: URLSession = .shared,
        credentialsStore: AuthenticationCredentialsStore = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.credentialsStore = credentialsStore
    }

    func signIn() async throws {
        let state = try Self.makeOAuthState()
        let authenticationURL = try makeAuthenticationURL(state: state)
        let code = try await requestAuthorizationCode(at: authenticationURL, expectedState: state)
        let credentials = try await exchangeAuthorizationCode(code)
        try credentialsStore.save(credentials)
    }

    private func requestAuthorizationCode(at authenticationURL: URL, expectedState: String) async throws -> String {
        guard let presenter = Self.topViewController() else {
            throw AuthenticationError.invalidConfiguration
        }

        return try await withCheckedThrowingContinuation { continuation in
            let authorizationController = RUDNAuthorizationViewController(
                authenticationURL: authenticationURL,
                callbackURL: configuration.authenticationCallbackURL,
                expectedState: expectedState
            ) { result in
                continuation.resume(with: result)
            }
            let navigationController = UINavigationController(rootViewController: authorizationController)
            navigationController.modalPresentationStyle = .formSheet
            navigationController.isModalInPresentation = true
            presenter.present(navigationController, animated: true)
        }
    }

    private func exchangeAuthorizationCode(_ code: String) async throws -> AuthenticationCredentials {
        var request = URLRequest(url: configuration.authorizationCodeExchangeURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AuthorizationCodeRequest(codeAnalitic: code))
        credentialsStore.addDeviceContext(to: &request)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidBackendResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw AuthenticationError.backendRejected(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        if let response = try? JSONDecoder().decode(BackendAuthenticationResponse.self, from: data) {
            return try response.toCredentials()
        }

        do {
            let envelope = try JSONDecoder().decode(BackendAuthenticationEnvelope.self, from: data)
            return try envelope.data.toCredentials()
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.invalidBackendResponse
        }
    }

    private func makeAuthenticationURL(state: String) throws -> URL {
        try OAuthFlow.makeAuthorizationURL(
            baseURL: configuration.authenticationURL,
            clientID: configuration.authenticationClientID,
            state: state
        )
    }

    private static func makeOAuthState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AuthenticationError.invalidConfiguration
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var controller = activeScene?.windows.first { $0.isKeyWindow }?.rootViewController

        while let presentedController = controller?.presentedViewController {
            controller = presentedController
        }
        return controller
    }

    private static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let message = String(data: data, encoding: .utf8)?
                .replacingOccurrences(of: "\u{feff}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return String(message.prefix(300))
    }
}

enum OAuthFlow {
    static func makeAuthorizationURL(baseURL: URL, clientID: String, state: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw AuthenticationError.invalidConfiguration
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { ["client_id", "response_type", "redirect_uri", "state"].contains($0.name) }
        queryItems.append(contentsOf: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state)
        ])
        components.queryItems = queryItems

        guard let url = components.url else {
            throw AuthenticationError.invalidConfiguration
        }
        return url
    }

    static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
            throw AuthenticationError.invalidState
        }
        guard let code = queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AuthenticationError.missingAuthorizationCode
        }
        return code
    }
}

private struct AuthorizationCodeRequest: Encodable {
    let codeAnalitic: String

    enum CodingKeys: String, CodingKey {
        case codeAnalitic = "code_analitic"
    }
}

private struct BackendAuthenticationResponse: Decodable {
    let token: String
    let username: String

    func toCredentials() throws -> AuthenticationCredentials {
        guard !token.isEmpty, !username.isEmpty else {
            throw AuthenticationError.invalidBackendResponse
        }
        return AuthenticationCredentials(token: token, username: username)
    }
}

private struct BackendAuthenticationEnvelope: Decodable {
    let data: BackendAuthenticationResponse
}

@MainActor
private final class RUDNAuthorizationViewController: UIViewController, WKNavigationDelegate {
    private let authenticationURL: URL
    private let callbackURL: URL
    private let expectedState: String
    private let completion: (Result<String, Error>) -> Void
    private var didFinish = false
    private var webView: WKWebView!

    init(
        authenticationURL: URL,
        callbackURL: URL,
        expectedState: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        self.authenticationURL = authenticationURL
        self.callbackURL = callbackURL
        self.expectedState = expectedState
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RUDN ID"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(cancelAuthorization)
        )
        webView.load(URLRequest(url: authenticationURL))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame != false,
              let url = navigationAction.request.url,
              isCallbackURL(url) else {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)

        do {
            finish(with: .success(try OAuthFlow.authorizationCode(from: url, expectedState: expectedState)))
        } catch {
            finish(with: .failure(error))
        }
    }

    @objc
    private func cancelAuthorization() {
        finish(with: .failure(AuthenticationError.cancelled))
    }

    private func isCallbackURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == callbackURL.scheme?.lowercased()
            && url.host?.lowercased() == callbackURL.host?.lowercased()
            && url.path == callbackURL.path
    }

    private func finish(with result: Result<String, Error>) {
        guard !didFinish else { return }
        didFinish = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        dismiss(animated: true) { [completion] in
            completion(result)
        }
    }
}
