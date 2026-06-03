import Foundation

// MARK: - Auth
struct LoginResponse: Codable {
    let user_id: Int
    let email: String
}

// MARK: - Rooms
struct Room: Codable, Identifiable {
    let id: Int
    let name: String
    let created_at: String
}

struct CreateRoomResponse: Codable {
    let room_id: Int
    let name: String
}

// MARK: - Anchors
struct Anchor: Codable, Identifiable {
    let id: Int
    let room_id: Int
    let label: String
    let pos: [Float]
    let normal: [Float]
    let objects: [LearningObject]
}

struct CreateAnchorResponse: Codable {
    let anchor_id: Int
}

// MARK: - Learning Objects
struct LearningObject: Codable, Identifiable {
    let id: Int
    let title: String
    let kind: String   // "text" | "link"
    let body: String
    let media_url: String
}

struct CreateObjectResponse: Codable {
    let object_id: Int
}

// MARK: - Review
struct ReviewResponse: Codable {
    let due: Int?       // nil when nothing due
    let review_id: Int?
    let object: LearningObject?
    let anchor: ReviewAnchorInfo?
}

struct ReviewAnchorInfo: Codable {
    let id: Int
    let pos: [Float]
    let normal: [Float]
}

// MARK: - Errors
enum APIError: LocalizedError {
    case badURL
    case server(String)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .badURL:         return "Invalid URL"
        case .server(let m): return m
        case .decode(let e): return "Decode error: \(e.localizedDescription)"
        }
    }
}
