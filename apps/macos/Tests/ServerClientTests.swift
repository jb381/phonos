import XCTest
@testable import Phonos

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ServerClientTests: XCTestCase {
    private var client: ServerClient!
    private var token: String = ""
    private var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        token = ""

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).wav")
        try? Data("fake-wav-data".utf8).write(to: tempFile)
        tempFileURL = tempFile

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        let session = URLSession(configuration: config)
        client = ServerClient(baseURL: "http://testserver.local:8765",
                              authToken: { [weak self] in self?.token ?? "" },
                              session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    // MARK: - Health Check

    func testHealthCheckSuccess() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"status":"ok","model":"base.en","device":"cpu","compute_type":"int8"}"#
            let response = HTTPURLResponse(url: URL(string: "http://testserver.local:8765/health")!,
                                           statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let result = try await client.healthCheck()
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.model, "base.en")
    }

    func testHealthCheckUnauthorized() async {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "http://testserver.local:8765/health")!,
                                           statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await client.healthCheck()
            XCTFail("Expected ServerError.unauthorized")
        } catch ServerError.unauthorized {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHealthCheckConnectionFailed() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        do {
            _ = try await client.healthCheck()
            XCTFail("Expected ServerError.connectionFailed")
        } catch ServerError.connectionFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Auth Header

    func testAuthHeaderPresentWhenTokenSet() async throws {
        token = "test-token-123"

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            XCTAssertEqual(auth, "Bearer test-token-123")

            let json = #"{"status":"ok","model":"base.en","device":"cpu","compute_type":"int8"}"#
            let response = HTTPURLResponse(url: URL(string: "http://testserver.local:8765/health")!,
                                           statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        _ = try await client.healthCheck()
    }

    func testAuthHeaderAbsentWhenTokenEmpty() async throws {
        token = ""

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            XCTAssertNil(auth)

            let json = #"{"status":"ok","model":"base.en","device":"cpu","compute_type":"int8"}"#
            let response = HTTPURLResponse(url: URL(string: "http://testserver.local:8765/health")!,
                                           statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        _ = try await client.healthCheck()
    }

    // MARK: - Error Response Decoding

    func testErrorResponseWithErrorKey() async {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"error":"Something went wrong"}"#
            let response = HTTPURLResponse(url: URL(string: "http://testserver.local:8765/health")!,
                                           statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        do {
            _ = try await client.healthCheck()
            XCTFail("Expected ServerError.serverError")
        } catch ServerError.serverError(let msg) {
            XCTAssertEqual(msg, "Something went wrong")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testErrorResponseWithDetailKey() async {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"detail":"Upload limit exceeded"}"#
            let response = HTTPURLResponse(url: URL(string: "http://testserver.local:8765/transcribe")!,
                                           statusCode: 413, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        do {
            _ = try await client.transcribe(fileURL: tempFileURL)
            XCTFail("Expected ServerError.serverError")
        } catch ServerError.serverError(let msg) {
            XCTAssertEqual(msg, "Upload limit exceeded")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Timeout

    func testTranscribeTimeoutReturns504() async {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"detail":"Timed out transcribing audio after 600 seconds"}"#
            let response = HTTPURLResponse(url: URL(string: "http://testserver.local:8765/transcribe")!,
                                           statusCode: 504, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        do {
            _ = try await client.transcribe(fileURL: tempFileURL)
            XCTFail("Expected ServerError.serverError")
        } catch ServerError.serverError(let msg) {
            XCTAssertTrue(msg.contains("Timed out"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
