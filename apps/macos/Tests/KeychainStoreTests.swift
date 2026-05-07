import XCTest
@testable import Phonos

final class KeychainStoreTests: XCTestCase {
    private let account = "test_token_\(UUID().uuidString)"
    private var didAccessKeychain = false

    /// Keychain access requires user interaction for unsigned test binaries.
    /// Tests are skipped by default. Set PHONOS_TEST_KEYCHAIN=1 to run them.
    ///
    /// CI strategy: These tests are intentionally skipped in GitHub Actions
    /// because unsigned Swift test binaries trigger Keychain permission dialogs
    /// that block the runner. For CI coverage, prefer a mocked Security-framework
    /// adapter; until one is added, these remain manual tests run locally.
    private static var keychainTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["PHONOS_TEST_KEYCHAIN"] == "1"
    }

    override func tearDown() {
        if didAccessKeychain {
            try? KeychainStore.delete(account: account)
        }
        super.tearDown()
    }

    private func skipIfKeychainUnavailable(file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(Self.keychainTestsEnabled, "Set PHONOS_TEST_KEYCHAIN=1 to run Keychain tests")
        didAccessKeychain = true
    }

    func testReadNonexistentReturnsNil() throws {
        try skipIfKeychainUnavailable()
        let result = try KeychainStore.read(account: account)
        XCTAssertNil(result)
    }

    func testWriteThenReadReturnsValue() throws {
        try skipIfKeychainUnavailable()
        try KeychainStore.set("secret123", account: account)
        let result = try KeychainStore.read(account: account)
        XCTAssertEqual(result, "secret123")
    }

    func testOverwriteReturnsNewValue() throws {
        try skipIfKeychainUnavailable()
        try KeychainStore.set("first", account: account)
        try KeychainStore.set("second", account: account)
        let result = try KeychainStore.read(account: account)
        XCTAssertEqual(result, "second")
    }

    func testSetEmptyStringDeletesItem() throws {
        try skipIfKeychainUnavailable()
        try KeychainStore.set("somevalue", account: account)
        try KeychainStore.set("", account: account)
        let result = try KeychainStore.read(account: account)
        XCTAssertNil(result)
    }

    func testDeleteNonexistentSucceeds() throws {
        try skipIfKeychainUnavailable()
        XCTAssertNoThrow(try KeychainStore.delete(account: account))
    }

    func testDeleteRemovesItem() throws {
        try skipIfKeychainUnavailable()
        try KeychainStore.set("delete-me", account: account)
        try KeychainStore.delete(account: account)
        let result = try KeychainStore.read(account: account)
        XCTAssertNil(result)
    }
}
