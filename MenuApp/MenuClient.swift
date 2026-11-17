import Combine
import Foundation

struct MenuClient {
    var session: URLSession = .shared

    func fetchMenu() async throws -> MenuDocument {
        let url = URL(string: "https://meny.cavabonga.no/menus/2/data/")!
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MenuClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MenuClientError.server(response.statusCode)
        }
        return try JSONDecoder().decode(MenuDocument.self, from: data)
    }
}

enum MenuClientError: LocalizedError {
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .server(404):
            return "The menu was not found. The menu API may not be deployed yet."
        case .server(let status):
            return "The menu server is unavailable (HTTP \(status)). Try again later."
        }
    }
}

@MainActor
final class MenuStore: ObservableObject {
    @Published private(set) var menu: MenuDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: MenuClient

    init(client: MenuClient = MenuClient()) {
        self.client = client
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let document = try await client.fetchMenu()
            try Task.checkCancellation()
            menu = document
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
