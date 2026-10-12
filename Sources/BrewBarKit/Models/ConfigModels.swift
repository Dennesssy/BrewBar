// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

public struct BrewConfigSection: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let content: String
}
