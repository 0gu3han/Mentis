import Foundation

final class APIClient {
    static let shared = APIClient()

    // Change this to your server's address (use your Mac's LAN IP when testing on a real device)
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "baseURL") ?? "http://10.0.0.39:5001" }
        set { UserDefaults.standard.set(newValue, forKey: "baseURL") }
    }

    var userId: Int? {
        get { UserDefaults.standard.object(forKey: "userId") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "userId") }
    }

    private let session = URLSession.shared
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Auth

    func login(email: String) async throws -> LoginResponse {
        var req = try makeRequest(path: "/auth/login", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        return try await send(req)
    }

    // MARK: - Rooms

    func listRooms() async throws -> [Room] {
        struct Wrapper: Codable { let rooms: [Room] }
        guard let uid = userId else { throw APIError.server("Not logged in") }
        let req = try makeRequest(path: "/rooms?user_id=\(uid)")
        return try await (send(req) as Wrapper).rooms
    }

    func createRoom(name: String, fileURL: URL) async throws -> CreateRoomResponse {
        guard let uid = userId else { throw APIError.server("Not logged in") }
        guard let url = URL(string: "\(baseURL)/rooms") else { throw APIError.badURL }

        let boundary = UUID().uuidString
        var req = URLRequest(url: url, timeoutInterval: 300) // 5 min — large GLB files
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try buildMultipart(boundary: boundary, fields: [
            ("user_id", "\(uid)"),
            ("name", name)
        ], fileURL: fileURL, fileField: "file")

        // Use upload(for:from:) — correct API for large body data uploads
        let (data, resp) = try await session.upload(for: req, from: body)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError.server(msg ?? "HTTP \(http.statusCode)")
        }
        return try decoder.decode(CreateRoomResponse.self, from: data)
    }

    // MARK: - Room File

    /// Downloads the room's 3D file to a local temp URL (USDZ or GLB depending on what was uploaded).
    func downloadRoomFile(roomId: Int) async throws -> URL {
        guard let url = URL(string: "\(baseURL)/rooms/\(roomId)/glb") else { throw APIError.badURL }
        let (tempURL, response) = try await session.download(from: url)
        let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let ext = mime.contains("usdz") ? "usdz" : mime.contains("gltf") ? "glb" : "glb"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("room_\(roomId).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    // MARK: - Anchors

    func listAnchors(roomId: Int) async throws -> [Anchor] {
        struct Wrapper: Codable { let anchors: [Anchor] }
        let req = try makeRequest(path: "/anchors?room_id=\(roomId)")
        return try await (send(req) as Wrapper).anchors
    }

    func createAnchor(roomId: Int, label: String, pos: [Float], normal: [Float]) async throws -> Int {
        var req = try makeRequest(path: "/anchors", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "room_id": roomId,
            "label": label,
            "pos": pos,
            "normal": normal
        ])
        let resp: CreateAnchorResponse = try await send(req)
        return resp.anchor_id
    }

    func deleteRoom(roomId: Int) async throws {
        let req = try makeRequest(path: "/rooms/\(roomId)", method: "DELETE")
        _ = try await session.data(for: req)
    }

    func deleteAnchor(id: Int) async throws {
        let req = try makeRequest(path: "/anchors/\(id)", method: "DELETE")
        _ = try await session.data(for: req)
    }

    // MARK: - Learning Objects

    func createObject(anchorId: Int, title: String, kind: String, body: String) async throws -> Int {
        var req = try makeRequest(path: "/objects", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "anchor_id": anchorId,
            "title": title,
            "kind": kind,
            "body": body
        ])
        let resp: CreateObjectResponse = try await send(req)
        return resp.object_id
    }

    // MARK: - Review

    func nextReview(roomId: Int? = nil) async throws -> ReviewResponse {
        var path = "/review/next"
        if let rid = roomId { path += "?room_id=\(rid)" }
        let req = try makeRequest(path: path)
        return try await send(req)
    }

    func submitReview(reviewId: Int, grade: Int) async throws {
        var req = try makeRequest(path: "/review/\(reviewId)", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["grade": grade])
        _ = try await session.data(for: req)
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError.server(msg ?? "HTTP \(http.statusCode)")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decode(error)
        }
    }

    private func buildMultipart(boundary: String, fields: [(String, String)], fileURL: URL, fileField: String) throws -> Data {
        var body = Data()
        let crlf = "\r\n"

        for (name, value) in fields {
            body.append("--\(boundary)\(crlf)".utf8Data)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".utf8Data)
            body.append("\(value)\(crlf)".utf8Data)
        }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mime = fileURL.pathExtension.lowercased() == "usdz" ? "model/vnd.usdz+zip" : "model/gltf-binary"
        body.append("--\(boundary)\(crlf)".utf8Data)
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\(crlf)".utf8Data)
        body.append("Content-Type: \(mime)\(crlf)\(crlf)".utf8Data)
        body.append(fileData)
        body.append("\(crlf)--\(boundary)--\(crlf)".utf8Data)

        return body
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
