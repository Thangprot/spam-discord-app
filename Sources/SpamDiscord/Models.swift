import Foundation

struct DiscordUser: Codable {
    let id: String
    let username: String
    let globalName: String?
}

struct Guild: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String?
}

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let type: Int
    let position: Int?
    let parentId: String?
    
    var isSendableText: Bool { type == 0 || type == 5 }
    var isCategory: Bool { type == 4 }
    var displayName: String { name ?? "không tên" }
}

struct ParsedMessage: Identifiable, Hashable {
    let id = UUID()
    let body: String
}

struct LogEntry: Identifiable {
    let id = UUID()
    let text: String
    let isSuccess: Bool
    let time = Date()
}