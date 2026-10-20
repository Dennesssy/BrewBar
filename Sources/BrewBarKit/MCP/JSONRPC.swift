// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Any JSON value. Used for JSON-RPC ids, params and results so ids echo back exactly as received.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .number(let number):
            // Integral values lose the ".0" so ids like 1 round-trip as 1. JSON has no NaN/Infinity.
            if !number.isFinite {
                try container.encodeNil()
            } else if number.rounded() == number, abs(number) < Self.maxExactInteger {
                try container.encode(Int64(number))
            } else {
                try container.encode(number)
            }
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }

    /// Value for `key` when this is an object; nil otherwise.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }

    public var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    public var intValue: Int? {
        guard case .number(let number) = self, number.isFinite,
              number.rounded() == number, abs(number) < Self.maxExactInteger else { return nil }
        return Int(number)
    }

    public var boolValue: Bool? {
        guard case .bool(let bool) = self else { return nil }
        return bool
    }

    /// Single-line JSON by default. `sortedKeys` keeps output deterministic.
    public func encodedString(prettyPrinted: Bool = false) -> String {
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if prettyPrinted { formatting.insert(.prettyPrinted) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    private static let maxExactInteger = 9_007_199_254_740_992.0
}

/// A parsed JSON-RPC 2.0 request. `id == nil` means notification: never answered.
public struct JSONRPCRequest: Sendable, Equatable {
    public let jsonrpc: String?
    public let id: JSONValue?
    public let method: String
    public let params: JSONValue?

    public var isNotification: Bool { id == nil }

    /// nil when `value` is not an object or has no string `method`.
    public init?(value: JSONValue) {
        guard case .object = value, let method = value["method"]?.stringValue else { return nil }
        self.jsonrpc = value["jsonrpc"]?.stringValue
        self.id = value["id"]
        self.method = method
        self.params = value["params"]
    }
}

/// Thrown from method handlers; converted into a JSON-RPC error response.
public struct JSONRPCError: Error, Sendable, Equatable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public static func invalidParams(_ message: String) -> JSONRPCError {
        JSONRPCError(code: JSONRPC.invalidParams, message: message)
    }
}

/// Response envelopes. Each returns one line of JSON with no trailing newline.
public enum JSONRPC {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    public static func result(id: JSONValue, _ result: JSONValue) -> String {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result
        ]).encodedString()
    }

    public static func error(id: JSONValue, code: Int, message: String) -> String {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object([
                "code": .number(Double(code)),
                "message": .string(message)
            ])
        ]).encodedString()
    }
}
