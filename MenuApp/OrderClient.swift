import Foundation

struct ShopStatus: Decodable, Equatable {
    let isOpen: Bool
    let message: String

    private enum CodingKeys: String, CodingKey {
        case isOpen = "is_open"
        case message
    }
}

struct OrderReceipt: Equatable {
    let id: Int
    let total: Decimal
}

struct OrderDraft {
    let submissionID: UUID
    let customerName: String
    let phone: String
    let note: String
    let items: [(dishID: Int, quantity: Int)]
}

enum BackendConfig {
    static let origin = URL(string: "https://meny.cavabonga.no")!
    static let webSocketURL = URL(string: "wss://meny.cavabonga.no/ws/shop/")!
    static let menuID = 2
}

struct OrderClient {
    var session: URLSession = .shared

    func fetchShop() async throws -> ShopStatus {
        var request = URLRequest(
            url: BackendConfig.origin.appending(path: "shop/status/"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(ShopStatus.self, from: data)
    }

    func submit(_ draft: OrderDraft) async throws -> OrderReceipt {
        let csrf = try await csrfToken()
        var request = URLRequest(
            url: BackendConfig.origin.appending(path: "menus/\(BackendConfig.menuID)/orders/"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
        request.setValue(BackendConfig.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(BackendConfig.origin.absoluteString + "/", forHTTPHeaderField: "Referer")
        let body: [String: Any] = [
            "submission_id": draft.submissionID.uuidString.lowercased(),
            "customer_name": draft.customerName,
            "phone": draft.phone,
            "note": draft.note,
            "items": draft.items.map { ["dish_id": $0.dishID, "quantity": $0.quantity] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OrderError.invalidResponse }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            if json?["error"] as? String == "shop_closed" {
                throw OrderError.shopClosed(json?["message"] as? String ?? "The shop is closed.")
            }
            if let errors = json?["errors"] as? [String: String], !errors.isEmpty {
                throw OrderError.rejected(errors.values.sorted().joined(separator: " "))
            }
            throw OrderError.server(http.statusCode)
        }
        guard let order = json?["order"] as? [String: Any],
              let id = order["id"] as? Int,
              let totalText = order["total"] as? String,
              let total = Decimal(string: totalText, locale: Locale(identifier: "en_US_POSIX")) else {
            throw OrderError.invalidResponse
        }
        return OrderReceipt(id: id, total: total)
    }

    // Django sets the CSRF cookie (prefixed per deployment, e.g. meny_csrftoken) on the shop page; URLSession stores it in its cookie jar.
    private func csrfToken() async throws -> String {
        let (_, response) = try await session.data(from: BackendConfig.origin)
        try Self.check(response)
        let cookies = session.configuration.httpCookieStorage?.cookies(for: BackendConfig.origin) ?? []
        guard let token = cookies.first(where: { $0.name.hasSuffix("csrftoken") })?.value else {
            throw OrderError.invalidResponse
        }
        return token
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw OrderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OrderError.server(http.statusCode) }
    }
}

enum OrderError: LocalizedError {
    case invalidResponse
    case server(Int)
    case shopClosed(String)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .server(let status):
            return "The order server is unavailable (HTTP \(status)). Try again later."
        case .shopClosed(let message), .rejected(let message):
            return message
        }
    }
}

/// Keeps a WebSocket open to the live backend and reports every event name it receives.
@MainActor
final class LiveConnection {
    private let session: URLSession
    private let onEvent: (String) -> Void
    private let onStateChange: (Bool) -> Void
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?

    init(
        session: URLSession = .shared,
        onEvent: @escaping (String) -> Void,
        onStateChange: @escaping (Bool) -> Void
    ) {
        self.session = session
        self.onEvent = onEvent
        self.onStateChange = onStateChange
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self else { return }
                if await self.listen() { delay = 1 }
                self.onStateChange(false)
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 15)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onStateChange(false)
    }

    /// Returns true if the connection was established before it ended.
    private func listen() async -> Bool {
        var request = URLRequest(url: BackendConfig.webSocketURL)
        request.setValue(BackendConfig.origin.absoluteString, forHTTPHeaderField: "Origin")
        let socket = session.webSocketTask(with: request)
        task = socket
        socket.resume()
        var connected = false
        do {
            // A successful ping proves the handshake completed; the server sends nothing on connect.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                socket.sendPing { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            connected = true
            onStateChange(true)
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            return false
        }
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let event = json["event"] as? String {
                    onEvent(event)
                }
            } catch {
                break
            }
        }
        socket.cancel(with: .goingAway, reason: nil)
        return connected
    }
}
