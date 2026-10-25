import Foundation

/// "Wrong item? Reclassify from a photo": the user retakes a photo of an item Moove misread (a
/// real scan called an e-scooter "vacuum"), and vision identifies it again from that photo,
/// ignoring the scan's category. No contract change: the photo goes through `add_item_photo`
/// like any other, with `?reclassify=1` on its URL (still an http(s) URL the module accepts;
/// the upload server ignores the query). The worker's vision agent sees the mark on the newest
/// photo, sends that photo first and says the scan may be wrong (`agents/src/agents/vision.ts`).
public enum ItemReclassify {
    public static let queryItem = "reclassify=1"

    /// `url` marked as a reclassification photo (once).
    public static func marking(_ url: String) -> String {
        if isMarked(url) { return url }
        return url + (url.contains("?") ? "&" : "?") + queryItem
    }

    /// True for a photo URL marked by `marking`.
    public static func isMarked(_ url: String) -> Bool {
        URLComponents(string: url)?.queryItems?.contains { $0.name == "reclassify" && $0.value == "1" } ?? false
    }

    /// The newest photo is a reclassification retake.
    public static func lastPhotoIsRetake(_ item: Item) -> Bool {
        item.photoUrls.last.map(isMarked) ?? false
    }

    /// Vision is identifying the item again from a retake.
    public static func isReclassifying(_ item: Item) -> Bool {
        lastPhotoIsRetake(item) && ItemLabels.isIdentifying(item)
    }

    /// The fix-it menu entry: "Not a vacuum? Take a photo" ("Wrong item? …" for a catch-all category).
    public static func menuTitle(for item: Item) -> String {
        let kind = item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if kind.isEmpty || ItemLabels.isPlaceholderName(kind, category: kind) || kind == ObjectSanity.relabelCategory {
            return "Wrong item? Take a photo"
        }
        let article = "aeiou".contains(kind.first!) ? "an" : "a"
        return "Not \(article) \(kind)? Take a photo"
    }

    /// The status line under the item's name while (or after) it's reclassified; nil when there's nothing to say.
    /// `offline`: the demo backend, where no worker will answer.
    public static func status(for item: Item, offline: Bool) -> String? {
        guard lastPhotoIsRetake(item) else { return nil }
        if ItemLabels.isIdentifying(item) {
            return offline
                ? "Waiting to reclassify from your photo (offline demo: no agents are running). Rename it below meanwhile."
                : "Reclassifying from your photo…"
        }
        if item.detailsStatus == .failed { return "Couldn't reclassify it from the photo. Rename it or pick what it is below." }
        return "Reclassified from your photo."
    }
}
