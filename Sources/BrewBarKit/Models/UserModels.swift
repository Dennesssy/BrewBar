import Foundation

public struct GitHubUser: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let login: String
    public let name: String?
    public let avatarUrl: String
    public let bio: String?
    public let publicRepos: Int
    public let followers: Int
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case name
        case avatarUrl = "avatar_url"
        case bio
        case publicRepos = "public_repos"
        case followers
        case createdAt = "created_at"
    }

    public init(id: Int, login: String, name: String? = nil, avatarUrl: String = "", bio: String? = nil, publicRepos: Int = 0, followers: Int = 0, createdAt: String = "") {
        self.id = id
        self.login = login
        self.name = name
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.publicRepos = publicRepos
        self.followers = followers
        self.createdAt = createdAt
    }
}

public enum DarkModeSetting: String, Codable, Sendable, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }
}

public struct UserPreferences: Codable, Sendable, Hashable {
    public var launchAtLogin: Bool
    public var showMenuBarIcon: Bool
    public var checkForAppUpdates: Bool
    public var darkMode: DarkModeSetting
    public var updateCheckInterval: TimeInterval
    public var defaultShell: String
    public var homebrewPrefix: String

    public init(
        launchAtLogin: Bool = true,
        showMenuBarIcon: Bool = true,
        checkForAppUpdates: Bool = true,
        darkMode: DarkModeSetting = .system,
        updateCheckInterval: TimeInterval = 3600,
        defaultShell: String = "zsh",
        homebrewPrefix: String = "/opt/homebrew/bin/brew"
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.checkForAppUpdates = checkForAppUpdates
        self.darkMode = darkMode
        self.updateCheckInterval = updateCheckInterval
        self.defaultShell = defaultShell
        self.homebrewPrefix = homebrewPrefix
    }
}

public struct UserReview: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let formulaId: String
    public let authorUsername: String
    public let rating: Int // 1 to 5
    public let comment: String
    public let date: Date
    public var helpfulVotes: Int

    public init(id: String = UUID().uuidString, formulaId: String, authorUsername: String, rating: Int, comment: String, date: Date = Date(), helpfulVotes: Int = 0) {
        self.id = id
        self.formulaId = formulaId
        self.authorUsername = authorUsername
        self.rating = rating
        self.comment = comment
        self.date = date
        self.helpfulVotes = helpfulVotes
    }
}

public struct UserFavorite: Codable, Sendable, Identifiable, Hashable {
    public var id: String { formulaId }
    public let formulaId: String
    public let addedDate: Date

    public init(formulaId: String, addedDate: Date = Date()) {
        self.formulaId = formulaId
        self.addedDate = addedDate
    }
}
