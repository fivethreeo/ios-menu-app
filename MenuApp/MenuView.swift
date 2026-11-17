import SwiftUI

struct MenuView: View {
    @StateObject private var store = MenuStore()
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
                if store.menu == nil {
                    await store.load()
                }
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
                            DishRow(dish: dish)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search the menu")
        .refreshable { await store.load() }
        .toolbar {
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
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
