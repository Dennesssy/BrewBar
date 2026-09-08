import Foundation

public actor HTTPClient {
    public static let shared = HTTPClient()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func request<T: Decodable>(_ url: URL, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrewBarError.networkError("Invalid response type")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw BrewBarError.networkError("HTTP status code \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BrewBarError.parseError("Failed to decode HTTP response: \(error.localizedDescription)")
        }
    }
}

public struct GitHubSearchResult: Codable, Sendable {
    public let items: [GitHubRepoItem]
}

public struct GitHubRepoItem: Codable, Sendable {
    public let name: String
    public let fullName: String
    public let description: String?
    public let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case description
        case htmlUrl = "html_url"
    }
}

public actor GitHubAPIClient {
    public static let shared = GitHubAPIClient()
    private let httpClient = HTTPClient.shared

    public init() {}

    public func searchFormulas(query: String) async throws -> [FormulaItem] {
        guard !query.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.github.com/search/repositories")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(query) topic:homebrew-formula")]

        guard let url = components?.url else {
            throw BrewBarError.networkError("Invalid search URL")
        }

        let result: GitHubSearchResult = try await httpClient.request(url, headers: [
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "BrewBar-App"
        ])

        return result.items.map { repo in
            FormulaItem(
                id: repo.name,
                name: repo.name,
                fullTitle: repo.fullName,
                description: repo.description ?? "",
                type: .formula,
                homepage: repo.htmlUrl,
                repository: repo.htmlUrl
            )
        }
    }
}

public actor NotaryScannerAPI {
    public static let shared = NotaryScannerAPI()

    public init() {}

    public func verifyCaskSafety(caskToken: String) async -> Bool {
        // Mock verification check for cask notarization / security
        return true
    }
}

public actor AnalyticsReporter {
    public static let shared = AnalyticsReporter()

    public init() {}

    public func trackEvent(name: String, parameters: [String: String] = [:]) async {
        // Anonymized telemetry stub respecting user privacy
        Logger.shared.debug("Analytics event tracked: \(name) with params \(parameters)")
    }
}
