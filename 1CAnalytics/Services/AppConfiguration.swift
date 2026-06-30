import Foundation

struct AppConfiguration {
    let analyticsBaseURL: URL
    let analyticsAPIKey: String?
    let useMockData: Bool

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        let baseURLString = bundle.object(forInfoDictionaryKey: "AnalyticsBaseURL") as? String
        let key = bundle.object(forInfoDictionaryKey: "AnalyticsAPIKey") as? String
        let useMockData = bundle.object(forInfoDictionaryKey: "AnalyticsUseMockData") as? String
        let fallbackURL = URL(string: "https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs/")!

        return AppConfiguration(
            analyticsBaseURL: baseURLString.flatMap(URL.init(string:)) ?? fallbackURL,
            analyticsAPIKey: key?.isEmpty == false ? key : nil,
            useMockData: useMockData?.uppercased() != "NO"
        )
    }
}
