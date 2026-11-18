import SwiftUI

struct CartView: View {
    @ObservedObject var cart: CartStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                if let shop = cart.shop, !shop.isOpen {
                    Section {
                        Label(shop.message, systemImage: "moon.zzz")
                    }
                }

                if let receipt = cart.receipt {
                    Section {
                        Label("Order #\(receipt.id) sent", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Total: \(receipt.total, format: .currency(code: "NOK"))")
                    }
                }

                if cart.lines.isEmpty {
                    Section {
                        Text("Your cart is empty.").foregroundStyle(.secondary)
                    }
                } else {
                    Section("Items") {
                        ForEach(cart.lines) { line in
                            CartLineRow(line: line, cart: cart)
                        }
                        .onDelete { offsets in
                            offsets.map { cart.lines[$0].dish }.forEach(cart.delete)
                        }
                        HStack {
                            Text("Total").font(.headline)
                            Spacer()
                            Text(cart.total, format: .currency(code: "NOK"))
                                .font(.headline.monospacedDigit())
                        }
                    }

                    Section("Your details") {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                        TextField("Phone", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Note (optional)", text: $note, axis: .vertical)
                    }

                    if let error = cart.errorMessage {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            Task {
                                if await cart.submit(name: name, phone: phone, note: note) {
                                    note = ""
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if cart.isSubmitting {
                                    ProgressView()
                                } else {
                                    Text(cart.isShopOpen ? "Send order" : "Closed for orders")
                                }
                                Spacer()
                            }
                        }
                        .disabled(!cart.canSubmit || !detailsValid)
                    }
                }
            }
            .navigationTitle("Cart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label(
                        cart.isLive ? "Live" : "Offline",
                        systemImage: cart.isLive ? "dot.radiowaves.left.and.right" : "wifi.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(cart.isLive ? .green : .secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        cart.dismissReceipt()
                        dismiss()
                    }
                }
            }
        }
    }

    private var detailsValid: Bool {
        let digits = phone.filter(\.isNumber).count
        return !name.trimmingCharacters(in: .whitespaces).isEmpty && (7...15).contains(digits)
    }
}

private struct CartLineRow: View {
    let line: CartLine
    @ObservedObject var cart: CartStore

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(line.dish.name)
                if let price = line.dish.price {
                    Text("\(price, format: .currency(code: "NOK")) × \(line.quantity)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Stepper(
                value: Binding(
                    get: { line.quantity },
                    set: { $0 > line.quantity ? cart.add(line.dish) : cart.remove(line.dish) }
                ),
                in: 0...CartStore.maxQuantity
            ) {
                Text("\(line.quantity)").monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel("Quantity of \(line.dish.name)")
        }
    }
}
