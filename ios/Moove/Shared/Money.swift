import Foundation
import MooveKit

extension Int64 {
    /// Formats integer cents as USD, e.g. 42000 -> "$420".
    var usd: String {
        (Double(self) / 100).formatted(.currency(code: "USD").precision(.fractionLength(self % 100 == 0 ? 0 : 2)))
    }
}

extension String {
    /// "pricing…" -> "Pricing…".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Item {
    /// Short label where an item's price goes: "$120", "identifying…", "pricing…", "no price".
    var priceText: String {
        switch priceState {
        case .priced(let cents): cents.usd
        case .identifying: "identifying…"
        case .pricing: "pricing…"
        case .unpriced: "no price"
        }
    }
}
