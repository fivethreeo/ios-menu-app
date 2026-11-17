import XCTest
@testable import MenuApp

final class MenuDocumentTests: XCTestCase {
    private let payload = """
    {
      "id": 2,
      "name": "Dinner",
      "categories": [
        {
          "id": 41,
          "name": "From the garden",
          "dishes": [
            {"id": 1, "name": "Soup", "description": "Roasted tomatoes",
             "price": "125.50", "allergens": ["milk"]},
            {"id": 2, "name": "Salad", "description": "",
             "price": null, "allergens": []}
          ]
        },
        {
          "id": 87,
          "name": "Seasonal specials",
          "dishes": [
            {"id": 3, "name": "Coffee", "description": "Freshly brewed",
             "price": "0.00", "allergens": []}
          ]
        }
      ]
    }
    """

    func testDecodesDynamicCategoriesAndDjangoDecimalPrices() throws {
        let menu = try decodeMenu()

        XCTAssertEqual(menu.categories.map(\.id), [41, 87])
        XCTAssertEqual(menu.categories.map(\.name), ["From the garden", "Seasonal specials"])
        XCTAssertEqual(menu.categories[0].dishes[0].price, Decimal(string: "125.50"))
        XCTAssertNil(menu.categories[0].dishes[1].price)
        XCTAssertEqual(menu.categories[1].dishes[0].price, Decimal.zero)
        XCTAssertEqual(menu.categories[0].dishes[0].allergens, ["milk"])
    }

    func testSearchTrimsWhitespaceAndCombinesWithCategoryFilter() throws {
        let menu = try decodeMenu()

        XCTAssertEqual(
            menu.filteredCategories(categoryID: 41, searchText: "  TOMATOES \n")
                .flatMap(\.dishes).map(\.id),
            [1]
        )
        XCTAssertTrue(menu.filteredCategories(categoryID: 87, searchText: "soup").isEmpty)
        XCTAssertEqual(
            menu.filteredCategories(categoryID: nil, searchText: "SEASONAL")
                .flatMap(\.dishes).map(\.id),
            [3]
        )
        XCTAssertEqual(
            menu.filteredCategories(categoryID: nil, searchText: " \n ").map(\.id),
            [41, 87]
        )
    }

    func testEmptyMenuAndUnmatchedSearchReturnNoCategories() throws {
        let menu = try decodeMenu()
        XCTAssertTrue(menu.filteredCategories(categoryID: nil, searchText: "missing").isEmpty)
        let empty = try JSONDecoder().decode(
            MenuDocument.self,
            from: Data(#"{"id":2,"name":"Dinner","categories":[]}"#.utf8)
        )
        XCTAssertTrue(empty.filteredCategories(categoryID: nil, searchText: "").isEmpty)
    }

    func testInvalidPricesFailDecodingInsteadOfBecomingFree() {
        for value in ["invalid", "-10.00", "NaN"] {
            let invalid = payload.replacingOccurrences(of: "125.50", with: value)
            XCTAssertThrowsError(
                try JSONDecoder().decode(MenuDocument.self, from: Data(invalid.utf8))
            )
        }
    }

    private func decodeMenu() throws -> MenuDocument {
        try JSONDecoder().decode(MenuDocument.self, from: Data(payload.utf8))
    }
}
