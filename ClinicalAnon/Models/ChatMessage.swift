//
//  ChatMessage.swift
//  Redactor
//
//  Purpose: Represents a message in the AI conversation
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Message Role

enum MessageRole: String, Codable {
    case user
    case assistant
}

// MARK: - Tool Use

/// Represents a tool call from the AI
struct ToolUse: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let input: [String: AnyCodable]

    /// Get input as dictionary for processing
    var inputDict: [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in input {
            result[key] = value.value
        }
        return result
    }
}

// MARK: - Any Codable Wrapper

/// Wrapper to handle arbitrary JSON values in tool input
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            var result: [String: Any] = [:]
            for (key, val) in dictValue {
                result[key] = val.value
            }
            value = result
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality check for common types
        switch (lhs.value, rhs.value) {
        case let (l as String, r as String): return l == r
        case let (l as Int, r as Int): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as Bool, r as Bool): return l == r
        default: return false
        }
    }
}

// MARK: - AI Response

/// Response from AI that may contain text and/or tool use
struct AIResponse {
    let text: String?
    let toolUse: ToolUse?
    let stopReason: String?

    var hasToolUse: Bool {
        toolUse != nil
    }

    var hasText: Bool {
        text != nil && !text!.isEmpty
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    var isUser: Bool {
        role == .user
    }

    var isAssistant: Bool {
        role == .assistant
    }
}

// MARK: - Convenience Initializers

extension ChatMessage {
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }
}

// MARK: - Tool Result Message

/// Represents a tool result to send back to the AI
struct ToolResultMessage {
    let toolUseId: String
    let content: String

    /// Convert to API format for messages array
    func toAPIFormat() -> [String: Any] {
        return [
            "role": "user",
            "content": [
                [
                    "type": "tool_result",
                    "tool_use_id": toolUseId,
                    "content": content
                ]
            ]
        ]
    }
}
