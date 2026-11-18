import SwiftUI

struct MenuView: View {
    @StateObject private var store = MenuStore()
    @StateObject private var cart = CartStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCart = false
    @State private var searchText = ""
    @State private var selectedCategoryID: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let menu = store.menu {
                    menuList(menu)
                } else if store.isLoading {
                    ProgressView("Loading menu...")
                } else {
                    ContentUnavailableView {
                        Label("Menu unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(store.errorMessage ?? "Connect to the internet to load the menu.")
                    } actions: {
                        Button("Try again") {
                            Task { await store.load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(store.menu?.name ?? "Menu")
            .task {
                cart.onMenuChanged = { Task { await store.load() } }
                cart.startLive()
                if store.menu == nil {
                    await store.load()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    cart.startLive()
                } else if phase == .background {
                    cart.stopLive()
                }
            }
            .onChange(of: store.menu?.categories.flatMap { $0.dishes.map(\.id) }) { _, _ in
                if let menu = store.menu { cart.prune(to: menu) }
            }
            .sheet(isPresented: $showCart) {
                CartView(cart: cart)
            }
            .onChange(of: store.menu?.categories.map(\.id)) { _, categoryIDs in
                if let selectedCategoryID,
                   !(categoryIDs ?? []).contains(selectedCategoryID) {
                    self.selectedCategoryID = nil
                }
            }
        }
    }

    private func menuList(_ menu: MenuDocument) -> some View {
        let categories = menu.filteredCategories(
            categoryID: selectedCategoryID,
            searchText: searchText
        )

        return List {
            if let error = store.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Retry refresh") {
                        Task { await store.load() }
                    }
                } footer: {
                    Text("Showing the previously loaded menu.")
                }
            }

            if categories.isEmpty {
                ContentUnavailableView(
                    "No dishes found",
                    systemImage: "fork.knife",
                    description: Text("Try another search or pull down to refresh.")
                )
            } else {
                ForEach(categories) { category in
                    Section(category.name) {
                        if category.dishes.isEmpty {
                            Text("No dishes available.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(category.dishes) { dish in
                            DishRow(dish: dish, quantity: cart.quantity(of: dish)) {
                                cart.add(dish)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search the menu")
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCart = true
                } label: {
                    Image(systemName: cart.itemCount > 0 ? "cart.fill" : "cart")
                        .overlay(alignment: .topTrailing) {
                            if cart.itemCount > 0 {
                                Text("\(cart.itemCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.red, in: Circle())
                                    .offset(x: 10, y: -10)
                            }
                        }
                }
                .accessibilityLabel("Cart, \(cart.itemCount) items")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $selectedCategoryID) {
                        Text("All categories")
                            .tag(Optional<Int>.none)
                        ForEach(menu.categories) { category in
                            Text(category.name)
                                .tag(Optional(category.id))
                        }
                    }
                } label: {
                    Label(
                        "Filter categories",
                        systemImage: selectedCategoryID == nil
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill"
                    )
                }
            }
        }
    }
}

private struct DishRow: View {
    let dish: Dish
    let quantity: Int
    let onAdd: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))

        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(dish.name)
                    .font(.headline)

                if !dish.description.isEmpty {
                    Text(dish.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let price = dish.price {
                Text(price, format: .currency(code: "NOK"))
                    .font(.body.monospacedDigit())
                    .fixedSize(horizontal: true, vertical: false)

                Button(action: onAdd) {
                    Label(
                        quantity > 0 ? "Add another \(dish.name) (\(quantity) in cart)" : "Add \(dish.name) to cart",
                        systemImage: "cart.badge.plus"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
