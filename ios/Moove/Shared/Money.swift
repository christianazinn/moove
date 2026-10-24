import Foundation

extension Int64 {
    /// Formats integer cents as USD, e.g. 42000 -> "$420".
    var usd: String {
        (Double(self) / 100).formatted(.currency(code: "USD").precision(.fractionLength(self % 100 == 0 ? 0 : 2)))
    }
}
