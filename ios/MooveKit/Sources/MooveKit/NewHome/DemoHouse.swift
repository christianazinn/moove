import Foundation

/// The hardcoded demo house (`Resources/demo-house.json`): the new home for
/// the live demo, and the fallback if a Zillow import fails.
public enum DemoHouse {
    private struct File: Decodable { var name: String }

    public static let json: String = {
        guard let url = Bundle.module.url(forResource: "demo-house", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("demo-house.json missing from the MooveKit bundle")
        }
        return String(decoding: data, as: UTF8.self)
    }()

    public static let name: String = (try? JSONDecoder().decode(File.self, from: Data(json.utf8)).name) ?? "Demo house"

    public static let floorPlan: FloorPlan = {
        do { return try FloorPlan(json: json) } catch { preconditionFailure("demo-house.json doesn't parse: \(error)") }
    }()
}
