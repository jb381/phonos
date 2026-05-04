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
    private let settings = SettingsManager.shared
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(settings.baseURL)\(path)") else {
            throw ServerError.connectionFailed("Invalid URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if !settings.authToken.isEmpty {
            req.setValue("Bearer \(settings.authToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        do {
            let (data, response) = try await session.data(for: req)
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

    func transcribe(fileURL: URL) async throws -> TranscriptionResponse {
        guard let url = URL(string: "\(settings.baseURL)/transcribe") else {
            throw ServerError.connectionFailed("Invalid URL")
        }

        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if !settings.authToken.isEmpty {
            req.setValue("Bearer \(settings.authToken)", forHTTPHeaderField: "Authorization")
        }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body

        do {
            let (data, response) = try await session.data(for: req)
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
            return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        } catch let e as ServerError {
            throw e
        } catch {
            throw ServerError.connectionFailed(error.localizedDescription)
        }
    }
}
