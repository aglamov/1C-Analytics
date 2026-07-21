import Foundation

struct AppConfiguration {
    let analyticsBaseURL: URL
    let analyticsAPIKey: String?
    let authenticationURL: URL
    let authenticationClientID: String
    let authenticationCallbackURL: URL
    let authorizationCodeExchangeURL: URL

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        let baseURLString = bundle.object(forInfoDictionaryKey: "AnalyticsBaseURL") as? String
        let key = bundle.object(forInfoDictionaryKey: "AnalyticsAPIKey") as? String
        let authenticationURLString = bundle.object(forInfoDictionaryKey: "AuthenticationURL") as? String
        let authenticationClientID = bundle.object(forInfoDictionaryKey: "AuthenticationClientID") as? String
        let authenticationCallbackURLString = bundle.object(forInfoDictionaryKey: "AuthenticationCallbackURL") as? String
        let authorizationCodeExchangeURLString = bundle.object(forInfoDictionaryKey: "AuthorizationCodeExchangeURL") as? String
        let fallbackURL = URL(string: "https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs/")!

        return AppConfiguration(
            analyticsBaseURL: baseURLString.flatMap(URL.init(string:)) ?? fallbackURL,
            analyticsAPIKey: key?.isEmpty == false ? key : nil,
            authenticationURL: authenticationURLString.flatMap(URL.init(string:)) ?? URL(string: "https://id.rudn.ru/sign-in")!,
            authenticationClientID: authenticationClientID?.isEmpty == false
                ? authenticationClientID!
                : "ed75cd5e-b477-4f3e-84b6-074608eee315",
            authenticationCallbackURL: authenticationCallbackURLString.flatMap(URL.init(string:))
                ?? URL(string: "https://sed.rudn.ru/DGU_DEMO/hs/DGU_APP_Mobile_Client/return_uri")!,
            authorizationCodeExchangeURL: authorizationCodeExchangeURLString.flatMap(URL.init(string:))
                ?? URL(string: "https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/auth/code")!
        )
    }
}
