import Foundation

struct AppConfiguration {
    let analyticsBaseURL: URL
    let analyticsPathToken: String?
    let analyticsAPIKey: String?

    var analyticsEndpointURL: URL {
        guard let analyticsPathToken else {
            return analyticsBaseURL
        }

        return analyticsBaseURL.appending(path: analyticsPathToken)
    }

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        let baseURLString = bundle.object(forInfoDictionaryKey: "AnalyticsBaseURL") as? String
        let pathToken = bundle.object(forInfoDictionaryKey: "AnalyticsPathToken") as? String
        let key = bundle.object(forInfoDictionaryKey: "AnalyticsAPIKey") as? String
        let fallbackURL = URL(string: "https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs/")!

        return AppConfiguration(
            analyticsBaseURL: baseURLString.flatMap(URL.init(string:)) ?? fallbackURL,
            analyticsPathToken: pathToken?.isEmpty == false ? pathToken : nil,
            analyticsAPIKey: key?.isEmpty == false ? key : nil
        )
    }
}
