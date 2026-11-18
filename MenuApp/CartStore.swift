import Combine
import Foundation

struct CartLine: Identifiable, Equatable {
    let dish: Dish
    var quantity: Int
    var id: Int { dish.id }

    static func == (lhs: CartLine, rhs: CartLine) -> Bool {
        lhs.dish.id == rhs.dish.id && lhs.quantity == rhs.quantity
    }
}

@MainActor
final class CartStore: ObservableObject {
    static let maxQuantity = 99
    static let maxLines = 50

    @Published private(set) var lines: [CartLine] = []
    @Published private(set) var shop: ShopStatus?
    @Published private(set) var isLive = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var receipt: OrderReceipt?
    @Published private(set) var errorMessage: String?

    private let client: OrderClient
    private var submissionID = UUID()
    private var connection: LiveConnection?
    var onMenuChanged: (() -> Void)?

    init(client: OrderClient = OrderClient()) {
        self.client = client
    }

    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }
    var total: Decimal { lines.reduce(0) { $0 + ($1.dish.price ?? 0) * Decimal($1.quantity) } }
    var isShopOpen: Bool { shop?.isOpen ?? true }
    var canSubmit: Bool { !lines.isEmpty && isShopOpen && !isSubmitting }

    func quantity(of dish: Dish) -> Int {
        lines.first { $0.dish.id == dish.id }?.quantity ?? 0
    }

    func add(_ dish: Dish) {
        guard dish.price != nil else { return }
        if let index = lines.firstIndex(where: { $0.dish.id == dish.id }) {
            guard lines[index].quantity < Self.maxQuantity else { return }
            lines[index].quantity += 1
        } else {
            guard lines.count < Self.maxLines else { return }
            lines.append(CartLine(dish: dish, quantity: 1))
        }
        changed()
    }

    func remove(_ dish: Dish) {
        guard let index = lines.firstIndex(where: { $0.dish.id == dish.id }) else { return }
        lines[index].quantity -= 1
        if lines[index].quantity <= 0 { lines.remove(at: index) }
        changed()
    }

    func delete(_ dish: Dish) {
        lines.removeAll { $0.dish.id == dish.id }
        changed()
    }

    /// Drops lines for dishes that disappeared from the menu after a live update.
    func prune(to menu: MenuDocument) {
        let available = Set(menu.categories.flatMap(\.dishes).map(\.id))
        let kept = lines.filter { available.contains($0.dish.id) }
        if kept.count != lines.count {
            lines = kept
            changed()
        }
    }

    func dismissReceipt() { receipt = nil }

    func startLive() {
        guard connection == nil else { return }
        let connection = LiveConnection(
            onEvent: { [weak self] event in
                guard let self else { return }
                if event == "shop.changed" {
                    Task { await self.refreshShop() }
                    self.onMenuChanged?()
                }
            },
            onStateChange: { [weak self] live in
                guard let self else { return }
                self.isLive = live
                // Anything may have changed while disconnected.
                if live {
                    Task { await self.refreshShop() }
                    self.onMenuChanged?()
                }
            }
        )
        self.connection = connection
        connection.start()
        Task { await refreshShop() }
    }

    func stopLive() {
        connection?.stop()
        connection = nil
    }

    func refreshShop() async {
        if let status = try? await client.fetchShop() { shop = status }
    }

    func submit(name: String, phone: String, note: String) async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let draft = OrderDraft(
            submissionID: submissionID,
            customerName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            items: lines.map { ($0.dish.id, $0.quantity) }
        )
        do {
            receipt = try await client.submit(draft)
            lines = []
            submissionID = UUID()
            return true
        } catch OrderError.shopClosed(let message) {
            shop = ShopStatus(isOpen: false, message: message)
            errorMessage = message
        } catch {
            // The same submission ID is kept so a retry cannot create a duplicate order.
            errorMessage = error.localizedDescription
        }
        return false
    }

    private func changed() {
        submissionID = UUID()
        errorMessage = nil
    }
}
