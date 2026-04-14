import Foundation
import os

actor TapesAPIClient {

    // MARK: - Configuration

    /// Must match the host used for `PUBLIC_SHARE_BASE` / Universal Links (see `docs/features/UniversalLinks.md`).
    #if DEBUG
    private let baseURL = URL(string: "https://tapes-api.hi-7d5.workers.dev")!
    #else
    private let baseURL = URL(string: "https://api.tapes.app")!
    #endif

    private static let tokenKey = "tapes_api_token"
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "API")

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Token Management

    var accessToken: String? {
        KeychainHelper.loadString(Self.tokenKey)
    }

    func storeToken(_ token: String) {
        KeychainHelper.save(token, for: Self.tokenKey)
    }

    func clearToken() {
        KeychainHelper.delete(Self.tokenKey)
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    // MARK: - Auth

    struct AuthResponse: Decodable {
        let accessToken: String
        let user: UserInfo

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case user
        }
    }

    struct UserInfo: Decodable {
        let userId: String
        let email: String?
        let name: String?
        let tier: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case email, name, tier
            case createdAt = "created_at"
        }
    }

    func authenticateWithApple(identityToken: Data, fullName: String?, email: String?) async throws -> AuthResponse {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw APIError.validation("Invalid identity token encoding.")
        }

        var body: [String: String] = ["identity_token": tokenString]
        if let name = fullName { body["full_name"] = name }
        if let email = email { body["email"] = email }

        let response: AuthResponse = try await post(path: "/auth/apple", body: body, authenticated: false)
        storeToken(response.accessToken)
        return response
    }

    // MARK: - Tapes

    struct CreateTapeResponse: Decodable {
        let tapeId: String
        let shareId: String
        let shareUrl: String
        let deepLink: String
        let createdAt: String
        let clipsUploaded: Bool?

        enum CodingKeys: String, CodingKey {
            case tapeId = "tape_id"
            case shareId = "share_id"
            case shareUrl = "share_url"
            case deepLink = "deep_link"
            case createdAt = "created_at"
            case clipsUploaded = "clips_uploaded"
        }
    }

    func createTape(tapeId: String, title: String, mode: String, expiresAt: String? = nil,
                    tapeSettings: [String: Any]? = nil) async throws -> CreateTapeResponse {
        var body: [String: Any] = [
            "tape_id": tapeId,
            "title": title,
            "mode": mode
        ]
        if let expiresAt { body["expires_at"] = expiresAt }
        if let settings = tapeSettings { body["tape_settings"] = settings }

        return try await postRaw(path: "/tapes", body: body)
    }

    struct TapeInfo: Decodable {
        let tapeId: String
        let title: String
        let mode: String
        let ownerId: String
        let shareId: String
        let shareIdCollab: String?
        let openAccess: Bool?
        let expiresAt: String?
        let createdAt: String
        let updatedAt: String
        let clipCount: Int
        let collaboratorCount: Int

        enum CodingKeys: String, CodingKey {
            case tapeId = "tape_id"
            case title, mode
            case ownerId = "owner_id"
            case shareId = "share_id"
            case shareIdCollab = "share_id_collab"
            case openAccess = "open_access"
            case expiresAt = "expires_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case clipCount = "clip_count"
            case collaboratorCount = "collaborator_count"
        }
    }

    struct OpenAccessResponse: Decodable {
        let tapeId: String
        let openAccess: Bool

        enum CodingKeys: String, CodingKey {
            case tapeId = "tape_id"
            case openAccess = "open_access"
        }
    }

    func getTape(tapeId: String) async throws -> TapeInfo {
        try await get(path: "/tapes/\(tapeId)")
    }

    func updateOpenAccess(tapeId: String, openAccess: Bool) async throws -> OpenAccessResponse {
        struct Body: Encodable { let open_access: Bool }
        return try await put(path: "/tapes/\(tapeId)/open-access", body: Body(open_access: openAccess))
    }

    func deleteTape(tapeId: String) async throws {
        try await delete(path: "/tapes/\(tapeId)")
    }

    // MARK: - Clips

    struct CreateClipResponse: Decodable {
        let clipId: String
        let uploadUrl: String
        let uploadUrlExpiresAt: String
        let thumbnailUploadUrl: String
        let orderIndex: Int

        enum CodingKeys: String, CodingKey {
            case clipId = "clip_id"
            case uploadUrl = "upload_url"
            case uploadUrlExpiresAt = "upload_url_expires_at"
            case thumbnailUploadUrl = "thumbnail_upload_url"
            case orderIndex = "order_index"
        }
    }

    func createClip(tapeId: String, clipId: String, type: String, durationMs: Int,
                    trimStartMs: Int? = nil, trimEndMs: Int? = nil, audioLevel: Double? = nil,
                    recordedAt: String? = nil, fileSizeBytes: Int? = nil,
                    contentType: String? = nil,
                    motionStyle: String? = nil, imageDurationMs: Int? = nil,
                    rotateQuarterTurns: Int? = nil, overrideScaleMode: String? = nil) async throws -> CreateClipResponse {
        var body: [String: Any] = [
            "clip_id": clipId,
            "type": type,
            "duration_ms": durationMs
        ]
        if let v = trimStartMs { body["trim_start_ms"] = v }
        if let v = trimEndMs { body["trim_end_ms"] = v }
        if let v = audioLevel { body["audio_level"] = v }
        if let v = recordedAt { body["recorded_at"] = v }
        if let v = fileSizeBytes { body["file_size_bytes"] = v }
        if let v = contentType { body["content_type"] = v }
        if let v = motionStyle { body["motion_style"] = v }
        if let v = imageDurationMs { body["image_duration_ms"] = v }
        if let v = rotateQuarterTurns { body["rotate_quarter_turns"] = v }
        if let v = overrideScaleMode { body["override_scale_mode"] = v }

        return try await postRaw(path: "/tapes/\(tapeId)/clips", body: body)
    }

    struct UploadConfirmResponse: Decodable {
        let clipId: String
        let orderIndex: Int
        let expiresAt: String
        let trackingRecordsCreated: Int

        enum CodingKeys: String, CodingKey {
            case clipId = "clip_id"
            case orderIndex = "order_index"
            case expiresAt = "expires_at"
            case trackingRecordsCreated = "tracking_records_created"
        }
    }

    func confirmUpload(tapeId: String, clipId: String, cloudUrl: String,
                       thumbnailUrl: String) async throws -> UploadConfirmResponse {
        let body = ["cloud_url": cloudUrl, "thumbnail_url": thumbnailUrl]
        return try await post(path: "/tapes/\(tapeId)/clips/\(clipId)/uploaded", body: body)
    }

    struct DownloadConfirmResponse: Decodable {
        let clipId: String
        let allDownloaded: Bool
        let assetDeleted: Bool

        enum CodingKeys: String, CodingKey {
            case clipId = "clip_id"
            case allDownloaded = "all_downloaded"
            case assetDeleted = "asset_deleted"
        }
    }

    func confirmDownload(tapeId: String, clipId: String) async throws -> DownloadConfirmResponse {
        try await postEmpty(path: "/tapes/\(tapeId)/clips/\(clipId)/downloaded")
    }

    // MARK: - Manifest

    func getManifest(tapeId: String) async throws -> TapeManifest {
        try await get(path: "/tapes/\(tapeId)/manifest")
    }

    // MARK: - Share

    struct ShareResolution: Decodable {
        let tapeId: String
        let title: String
        let mode: String
        let ownerName: String?
        let clipCount: Int
        let status: String
        let userRole: String
        let manifestUrl: String

        enum CodingKeys: String, CodingKey {
            case tapeId = "tape_id"
            case title, mode
            case ownerName = "owner_name"
            case clipCount = "clip_count"
            case status
            case userRole = "user_role"
            case manifestUrl = "manifest_url"
        }
    }

    func resolveShare(shareId: String) async throws -> ShareResolution {
        try await get(path: "/share/\(shareId)")
    }

    // MARK: - Collaborators

    struct CollaboratorInfo: Decodable, Identifiable {
        let userId: String?
        let email: String
        let name: String?
        let role: String
        let status: String
        let accessMode: String?
        let joinedAt: String?

        var id: String { userId ?? email }
        var displayName: String { name ?? email }

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case email, name, role, status
            case accessMode = "access_mode"
            case joinedAt = "joined_at"
        }
    }

    struct CollaboratorListResponse: Decodable {
        let collaborators: [CollaboratorInfo]
    }

    func listCollaborators(tapeId: String) async throws -> [CollaboratorInfo] {
        let response: CollaboratorListResponse = try await get(path: "/tapes/\(tapeId)/collaborators")
        return response.collaborators
    }

    func inviteCollaborator(tapeId: String, email: String, role: String = "collaborator", accessMode: String = "view") async throws {
        let body = ["email": email, "role": role, "access_mode": accessMode]
        let _: CollaboratorInfo = try await post(path: "/tapes/\(tapeId)/collaborators", body: body)
    }

    func updateRole(tapeId: String, userId: String, role: String) async throws {
        let body = ["role": role]
        let _: [String: String] = try await put(path: "/tapes/\(tapeId)/collaborators/\(userId)/role", body: body)
    }

    func revokeCollaborator(tapeId: String, identifier: String) async throws {
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        try await delete(path: "/tapes/\(tapeId)/collaborators/\(encoded)")
    }

    // MARK: - Sync

    struct SyncPushResponse: Decodable {
        let notifiedCount: Int
        let nextAvailableAt: String

        enum CodingKeys: String, CodingKey {
            case notifiedCount = "notified_count"
            case nextAvailableAt = "next_available_at"
        }
    }

    func syncPush(tapeId: String) async throws -> SyncPushResponse {
        try await postEmpty(path: "/tapes/\(tapeId)/sync-push")
    }

    // MARK: - Validate

    struct TapeValidation: Decodable {
        let tapeId: String
        let title: String
        let mode: String
        let status: String
        let role: String
        let clipCount: Int
        let pendingDownloads: Int
        let expiresAt: String?
        let permissions: ValidationPermissions

        enum CodingKeys: String, CodingKey {
            case tapeId = "tape_id"
            case title, mode, status, role
            case clipCount = "clip_count"
            case pendingDownloads = "pending_downloads"
            case expiresAt = "expires_at"
            case permissions
        }
    }

    struct ValidationPermissions: Decodable {
        let canContribute: Bool
        let canExport: Bool
        let canSaveToDevice: Bool
        let canInvite: Bool

        enum CodingKeys: String, CodingKey {
            case canContribute = "can_contribute"
            case canExport = "can_export"
            case canSaveToDevice = "can_save_to_device"
            case canInvite = "can_invite"
        }
    }

    func validateTape(tapeId: String) async throws -> TapeValidation {
        try await get(path: "/tapes/\(tapeId)/validate")
    }

    // MARK: - Shared Tapes

    func getSharedTapes() async throws -> [SharedTapeItem] {
        try await get(path: "/tapes/shared")
    }

    // MARK: - Device Token

    func updateDeviceToken(_ token: String) async throws {
        let body = ["device_token": token, "platform": "ios"]
        try await putNoResponse(path: "/users/me/device-token", body: body)
    }

    // MARK: - User

    func getMe() async throws -> UserInfo {
        try await get(path: "/users/me")
    }

    // MARK: - HTTP Primitives

    private func get<T: Decodable>(path: String) async throws -> T {
        let request = try buildRequest(method: "GET", path: path)
        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(path: String, body: B, authenticated: Bool = true) async throws -> T {
        var request = try buildRequest(method: "POST", path: path, authenticated: authenticated)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    private func postRaw<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var request = try buildRequest(method: "POST", path: path)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    private func postEmpty<T: Decodable>(path: String) async throws -> T {
        let request = try buildRequest(method: "POST", path: path)
        return try await execute(request)
    }

    private func put<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        var request = try buildRequest(method: "PUT", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    private func putNoResponse<B: Encodable>(path: String, body: B) async throws {
        var request = try buildRequest(method: "PUT", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.network(URLError(.badServerResponse)) }

        if http.statusCode >= 400 {
            throw APIError.from(status: http.statusCode, body: data)
        }
    }

    private func delete(path: String) async throws {
        let request = try buildRequest(method: "DELETE", path: path)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.network(URLError(.badServerResponse)) }

        if http.statusCode >= 400 {
            throw APIError.from(status: http.statusCode, body: data)
        }
    }

    // MARK: - Request Building

    private func buildRequest(method: String, path: String, authenticated: Bool = true) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method

        if authenticated {
            guard let token = accessToken else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Response Handling

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            log.error("Network request failed: \(error.localizedDescription)")
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        log.debug("\(request.httpMethod ?? "?") \(request.url?.path ?? "?") → \(http.statusCode)")

        if http.statusCode >= 400 {
            throw APIError.from(status: http.statusCode, body: data)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            log.error("Decoding failed for \(T.self): \(error.localizedDescription)")
            throw APIError.decodingFailed(error)
        }
    }
}
