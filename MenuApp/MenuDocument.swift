import Foundation

struct MenuDocument: Decodable {
    let id: Int
    let name: String
    let categories: [MenuCategory]

    func filteredCategories(categoryID: Int?, searchText: String) -> [MenuCategory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return categories.compactMap { category in
            guard categoryID == nil || categoryID == category.id else { return nil }
            guard !query.isEmpty else { return category }

            let matchesCategory = category.name.localizedCaseInsensitiveContains(query)
            let dishes = category.dishes.filter { dish in
                matchesCategory
                    || dish.name.localizedCaseInsensitiveContains(query)
                    || dish.description.localizedCaseInsensitiveContains(query)
            }
            guard matchesCategory || !dishes.isEmpty else { return nil }
            return MenuCategory(id: category.id, name: category.name, dishes: dishes)
        }
    }
}

struct MenuCategory: Decodable, Identifiable {
    let id: Int
    let name: String
    let dishes: [Dish]
}

struct Dish: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String
    let price: Decimal?
    let allergens: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, price, allergens
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decode(String.self, forKey: .description)
        allergens = try values.decode([String].self, forKey: .allergens)

        if let text = try values.decodeIfPresent(String.self, forKey: .price) {
            guard let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
                  !amount.isNaN, amount >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .price,
                    in: values,
                    debugDescription: "Expected a nonnegative decimal price."
                )
            }
            price = amount
        } else {
            price = nil
        }
    }
}
