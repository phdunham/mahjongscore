import Foundation

/// The canonical tai rule table, loaded from the bundled Rules.json.
public struct RuleTable: Codable, Sendable {
    public let source: String
    public let variant: String
    public let fetchedAt: String
    public let patterns: [PatternRule]

    public struct PatternRule: Hashable, Codable, Sendable {
        public let id: String
        public let nameZh: String
        public let nameEn: String
        public let tai: Int
        public let category: String
        public let description: String
        public let descriptionEn: String
    }

    public enum LoadError: Error, Equatable {
        case resourceMissing
    }

    public func rule(id: String) -> PatternRule {
        guard let r = patterns.first(where: { $0.id == id }) else {
            fatalError("Missing rule in Rules.json: \(id). This is a bug — Scorer expects every referenced id to exist in the bundled rule table.")
        }
        return r
    }

    public static func load() throws -> RuleTable {
        guard let url = Bundle.module.url(forResource: "Rules", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuleTable.self, from: data)
    }
}
