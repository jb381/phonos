import Foundation

struct HealthResponse: Codable {
    let status: String
    let model: String
    let device: String
    let compute_type: String
}

struct ModelsResponse: Codable {
    let models: [String]
    let active: String
}

struct ActiveModelResponse: Codable {
    let model: String
    let status: String
}

struct SetModelRequest: Codable {
    let model: String
}

struct TranscriptionResponse: Codable {
    let text: String
    let model: String
    let language: String
    let duration_seconds: Double
    let processing_seconds: Double
}

struct ErrorResponse: Decodable {
    let message: String

    private enum CodingKeys: String, CodingKey {
        case error
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let error = try container.decodeIfPresent(String.self, forKey: .error) {
            message = error
        } else if let detail = try container.decodeIfPresent(String.self, forKey: .detail) {
            message = detail
        } else {
            message = "Unknown server error"
        }
    }
}

enum ServerError: LocalizedError {
    case connectionFailed(String)
    case unauthorized
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .unauthorized: return "Authentication failed"
        case .serverError(let msg): return "Server error: \(msg)"
        case .invalidResponse: return "Invalid response from server"
        }
    }
}

actor ServerClient {
    private let baseURL: String
    private let authToken: () -> String
    private let session: URLSession

    private var _activeTask: Task<TranscriptionResponse, Error>?

    init() {
        let settings = SettingsManager.shared
        self.baseURL = settings.baseURL
        self.authToken = { settings.authToken }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 650
        config.timeoutIntervalForResource = 650
        self.session = URLSession(configuration: config)
    }

    init(baseURL: String, authToken: @escaping () -> String, session: URLSession) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.authToken = authToken
        self.session = session
    }

    func cancelTranscription() {
        _activeTask?.cancel()
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResponse {
        guard let url = URL(string: "\(baseURL)/transcribe") else {
            throw ServerError.connectionFailed("Invalid URL")
        }

        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        authHeader(for: &req)

        let filename = fileURL.lastPathComponent
        let preamble = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n" +
            "Content-Type: audio/wav\r\n\r\n"
        let postamble = "\r\n--\(boundary)--\r\n"

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonos_upload_\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        FileManager.default.createFile(atPath: tmpURL.path, contents: nil, attributes: nil)
        let outHandle = try FileHandle(forWritingTo: tmpURL)
        defer { try? outHandle.close() }
        try outHandle.write(contentsOf: preamble.data(using: .utf8)!)

        let inHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? inHandle.close() }
        while let chunk = try inHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try outHandle.write(contentsOf: chunk)
        }
        try outHandle.write(contentsOf: postamble.data(using: .utf8)!)

        let task = Task<TranscriptionResponse, Error> {
            do {
                let (data, response) = try await session.upload(for: req, fromFile: tmpURL)
                let _ = try handleResponse(data: data, response: response)
                return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            } catch let e as ServerError {
                throw e
            } catch {
                throw ServerError.connectionFailed(error.localizedDescription)
            }
        }
        _activeTask = task

        do {
            return try await task.value
        } catch is CancellationError {
            throw ServerError.connectionFailed("Transcription cancelled")
        }
    }

    private func authHeader(for request: inout URLRequest) {
        let token = authToken()
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func handleResponse(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw ServerError.invalidResponse
        }
        if http.statusCode == 401 {
            throw ServerError.unauthorized
        }
        if http.statusCode >= 400 {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw ServerError.serverError(err.message)
            }
            throw ServerError.serverError("HTTP \(http.statusCode)")
        }
        return data
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ServerError.connectionFailed("Invalid URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        authHeader(for: &req)

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        do {
            let (data, response) = try await session.data(for: req)
            return try handleResponse(data: data, response: response)
        } catch let e as ServerError {
            throw e
        } catch {
            throw ServerError.connectionFailed(error.localizedDescription)
        }
    }

    func healthCheck() async throws -> HealthResponse {
        let data = try await request("/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func listModels() async throws -> ModelsResponse {
        let data = try await request("/models")
        return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    func setActiveModel(_ model: String) async throws -> ActiveModelResponse {
        let body = try JSONEncoder().encode(SetModelRequest(model: model))
        let data = try await request("/models/active", method: "PUT", body: body)
        return try JSONDecoder().decode(ActiveModelResponse.self, from: data)
    }
}
