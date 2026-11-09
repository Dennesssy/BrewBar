// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

public actor HTTPClient {
    public static let shared = HTTPClient()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func request<T: Decodable>(_ url: URL, headers: [String: String] = [:]) async throws -> T {
        let data = try await fetchRawData(url, headers: headers)
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BrewBarError.parseError("Failed to decode HTTP response: \(error.localizedDescription)")
        }
    }

    /// Raw bytes, so callers that need to cache the response to disk (e.g. a
    /// large catalog payload) aren't forced to re-encode a decoded value.
    public func fetchRawData(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
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

        return data
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
        components?.queryItems = [URLQueryItem(
            name: "q",
            value: "\(query) (topic:homebrew-formula OR topic:homebrew-cask)"
        )]

        guard let url = components?.url else {
            throw BrewBarError.networkError("Invalid search URL")
        }

        var headers = [
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "BrewBar-App"
        ]
        // The Preferences token exists for exactly this: anonymous search is
        // 10 req/min, authenticated is 30.
        if let token = try? KeychainManager.shared.retrieveToken(service: AppIdentity.githubKeychainService),
           !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }

        let result: GitHubSearchResult = try await httpClient.request(url, headers: headers)

        return result.items.map { repo in
            FormulaItem(
                id: repo.name,
                name: repo.name,
                fullTitle: repo.fullName,
                description: repo.description ?? "",
                type: .formula,
                homepage: repo.htmlUrl,
                repository: repo.htmlUrl,
                isRemoteSuggestion: true
            )
        }
    }
}

