import Foundation

/// #276: when vision isn't sure of the exact product and one photo would settle it, ask for
/// that photo, but only where the exact model moves the price (likely $100+ or electronics).
extension Item {
    /// The ask shown on Item detail, or nil when no close-up is wanted.
    public var closeupRequest: String? {
        guard let hint = closeupPhoto, worthACloseup else { return nil }
        return "Moove isn't sure which model this is. A photo of the \(hint) would pin down its price."
    }

    /// The hint as a noun phrase ("model sticker on the back"), when it applies.
    var closeupPhoto: String? {
        guard let confidence = identifyConfidence, confidence != .high,
              detailsStatus != .pending, detailsStatus != .running else { return nil }
        var hint = (closeupHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["a ", "an ", "the "] where hint.lowercased().hasPrefix(article) {
            hint = String(hint.dropFirst(article.count))
        }
        hint = hint.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return hint.isEmpty ? nil : hint
    }

    private var worthACloseup: Bool {
        if let value = estValueCents { return value >= 10_000 || Self.isElectronics(category: category, name: name) }
        return Self.isElectronics(category: category, name: name) || !(brand ?? "").isEmpty
    }

    static func isElectronics(category: String, name: String) -> Bool {
        let words = Set("\(category) \(name)".lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !words.isDisjoint(with: [
            "electronics", "tv", "television", "monitor", "laptop", "macbook", "computer", "pc", "phone", "iphone",
            "tablet", "ipad", "camera", "speaker", "speakers", "console", "playstation", "xbox", "nintendo",
            "headphones", "projector", "printer", "keyboard", "synthesizer", "amplifier", "receiver",
        ])
    }
}

extension Review {
    /// Items where one more photo would identify the exact product, most valuable first.
    public static func wantingCloseups(_ items: [Item]) -> [Item] {
        items.filter { $0.closeupRequest != nil }.sorted { ($0.estValueCents ?? 0) > ($1.estValueCents ?? 0) }
    }
}
