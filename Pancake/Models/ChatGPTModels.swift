import Foundation

// MARK: - Timeout Error
struct TimeoutError: Error {
    let message = "Request timed out"
}

// MARK: - ChatGPT API Models
struct ChatGPTRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int?
    let temperature: Double?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatGPTResponse: Codable {
    let choices: [ChatChoice]
    let usage: TokenUsage?
}

struct ChatChoice: Codable {
    let message: ChatMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct TokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Music Suggestion Models
struct MusicSuggestion: Codable, Identifiable {
    let id: UUID
    let songTitle: String
    let artist: String
    let reason: String
    let mood: MusicMood
    let confidence: Double // 0.0 to 1.0
    
    init(songTitle: String, artist: String, reason: String, mood: MusicMood, confidence: Double = 0.8) {
        self.id = UUID()
        self.songTitle = songTitle
        self.artist = artist
        self.reason = reason
        self.mood = mood
        self.confidence = confidence
    }
}
