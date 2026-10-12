// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

public struct DoctorIssue: Identifiable, Sendable {
    public let id = UUID()
    public let severity: Severity
    public let summary: String
    public let details: String
    public let fixCommand: [String]?

    public enum Severity: Int, Comparable, Sendable {
        case warning = 1
        case error = 2
        
        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
}
