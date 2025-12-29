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
