import XCTest
import Supabase
@testable import Saku

/// Answers every request with an empty list and remembers the last request, so a test can read the headers that were sent.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var last: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubProtocol.last = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SpaceStoreTests: XCTestCase {
    private let sample = "AAAAAAAA-0000-0000-0000-000000000001"

    override func setUp() { SpaceStore.clear(); StubProtocol.last = nil }
    override func tearDown() { SpaceStore.clear() }

    private func client() -> SpaceClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let base = SupabaseClient(supabaseURL: URL(string: "https://example.test")!, supabaseKey: "anon",
                                  options: .init(global: .init(session: URLSession(configuration: config))))
        return SpaceClient(base: base)
    }

    func testNormalizesToLowercaseUUIDAndRejectsAnythingElse() {
        XCTAssertEqual(SpaceStore.normalized(sample), sample.lowercased())
        XCTAssertNil(SpaceStore.normalized("not-a-uuid"))
        XCTAssertNil(SpaceStore.normalized(""))
        XCTAssertNil(SpaceStore.normalized(nil))
    }

    func testSetAndClear() {
        SpaceStore.setActive(sample)
        XCTAssertEqual(SpaceStore.activeSpaceId, sample.lowercased())
        SpaceStore.setActive("junk")          // never stored: the server would refuse it
        XCTAssertNil(SpaceStore.activeSpaceId)
        SpaceStore.setActive(sample)
        SpaceStore.clear()
        XCTAssertNil(SpaceStore.activeSpaceId)
    }

    func testSurvivesAProcessRestart() {
        SpaceStore.setActive(sample)
        // a fresh process (Siri/Shortcuts) has an empty cache and reads the App Group
        UserDefaults(suiteName: ShareInbox.appGroup)?.synchronize()
        XCTAssertEqual(UserDefaults(suiteName: ShareInbox.appGroup)?.string(forKey: "activeSpaceId"), sample.lowercased())
    }

    func testSelectCarriesTheHeader() async throws {
        SpaceStore.setActive(sample)
        _ = try await client().from("accounts").select().execute()
        XCTAssertEqual(StubProtocol.last?.value(forHTTPHeaderField: "x-saku-space"), sample.lowercased())
    }

    func testRpcCarriesTheHeader() async throws {
        SpaceStore.setActive(sample)
        _ = try await client().rpc("cancel_pending_payday").execute()
        XCTAssertEqual(StubProtocol.last?.value(forHTTPHeaderField: "x-saku-space"), sample.lowercased())
        _ = try await client().rpc("set_payday", params: ["p_day": 25]).execute()
        XCTAssertEqual(StubProtocol.last?.value(forHTTPHeaderField: "x-saku-space"), sample.lowercased())
    }

    func testNoHeaderWithoutAWorkspace() async throws {
        _ = try await client().from("accounts").select().execute()
        XCTAssertNil(StubProtocol.last?.value(forHTTPHeaderField: "x-saku-space"))
    }

    func testPersonalClientNeverSendsTheHeader() async throws {
        SpaceStore.setActive(sample)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let plain = SupabaseClient(supabaseURL: URL(string: "https://example.test")!, supabaseKey: "anon",
                                   options: .init(global: .init(session: URLSession(configuration: config))))
        _ = try await plain.from("user_profiles").select().execute()
        XCTAssertNil(StubProtocol.last?.value(forHTTPHeaderField: "x-saku-space"))
    }

    func testStaleWorkspaceFallsBackToPersonal() {
        SpaceStore.setActive(sample)
        struct Refused: Error, CustomStringConvertible { let description = "PostgrestError(message: \"space_forbidden\")" }
        struct Other: Error {}
        XCTAssertFalse(SpaceStore.recover(from: Other()))
        XCTAssertEqual(SpaceStore.activeSpaceId, sample.lowercased())
        XCTAssertTrue(SpaceStore.recover(from: Refused()))
        XCTAssertNil(SpaceStore.activeSpaceId)
    }

    func testProfileDecodesDefaultSpace() throws {
        let json = """
        {"id":"\(UUID().uuidString)","auth_user_id":"\(UUID().uuidString)","default_currency_code":"IDR","locale":"id","timezone":"Asia/Jakarta","default_space_id":"\(sample)"}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.defaultSpaceId?.uuidString, sample)
    }
}
