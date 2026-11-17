import Foundation
import XCTest
@testable import MenuApp

final class MenuClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MenuURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        MenuURLProtocol.handler = nil
        super.tearDown()
    }

    func testHTTPFailureIsReportedBeforeDecodingResponse() async {
        MenuURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://meny.cavabonga.no/menus/2/data/")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return (503, Data("<html>Unavailable</html>".utf8))
        }

        do {
            _ = try await MenuClient(session: session).fetchMenu()
            XCTFail("Expected an HTTP error")
        } catch MenuClientError.server(let status) {
            XCTAssertEqual(status, 503)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFailedRefreshKeepsPreviouslyLoadedMenuAndCanBeRetried() async {
        MenuURLProtocol.handler = { _ in
            (200, Data(#"{"id":2,"name":"Dinner","categories":[]}"#.utf8))
        }
        let store = MenuStore(client: MenuClient(session: session))
        await store.load()
        XCTAssertEqual(store.menu?.name, "Dinner")
        XCTAssertNil(store.errorMessage)

        MenuURLProtocol.handler = { _ in (503, Data()) }
        await store.load()
        XCTAssertEqual(store.menu?.name, "Dinner")
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)

        MenuURLProtocol.handler = { _ in
            (200, Data(#"{"id":2,"name":"Updated dinner","categories":[]}"#.utf8))
        }
        await store.load()
        XCTAssertEqual(store.menu?.name, "Updated dinner")
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }
}

private final class MenuURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler, let url = request.url else {
                throw URLError(.badServerResponse)
            }
            let (status, data) = try handler(request)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
