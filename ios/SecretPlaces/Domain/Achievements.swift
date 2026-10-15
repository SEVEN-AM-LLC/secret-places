import SwiftUI

/// Collectible badges, earned by marking secrets as visited ("I've been here").
/// Computed on device from the user's visited places — nothing extra is stored or sent.
struct Achievement: Identifiable, Equatable {
    let id: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let earned: Bool

    static func == (a: Achievement, b: Achievement) -> Bool { a.id == b.id && a.earned == b.earned }
}

enum Achievements {
    /// All badges, earned or not, in display order.
    static func evaluate(visited: [PlaceTeaser], categorySlug: (String?) -> String?) -> [Achievement] {
        let n = visited.count
        let perCity = Dictionary(grouping: visited, by: { $0.cityId ?? "" }).mapValues(\.count)
        let slugs = visited.map { categorySlug($0.primaryCategoryId) }
        func count(_ set: Set<String>) -> Int { slugs.filter { $0.map(set.contains) ?? false }.count }

        return [
            .init(id: "first", title: "First secret", detail: "Visit your first hidden place", symbol: "key", earned: n >= 1),
            .init(id: "explorer", title: "Explorer", detail: "Visit 5 secrets", symbol: "map", earned: n >= 5),
            .init(id: "insider", title: "Insider", detail: "Visit 15 secrets", symbol: "eye", earned: n >= 15),
            .init(id: "legend", title: "Legend", detail: "Visit 50 secrets", symbol: "crown", earned: n >= 50),
            .init(id: "local", title: "Honorary local", detail: "Visit 5 secrets in one city", symbol: "house", earned: (perCity.values.max() ?? 0) >= 5),
            .init(id: "globetrotter", title: "Globetrotter", detail: "Find secrets in 3 cities", symbol: "globe.europe.africa", earned: perCity.count >= 3),
            .init(id: "night", title: "Night owl", detail: "Visit 3 bars or night spots", symbol: "moon.stars", earned: count(["bars", "night"]) >= 3),
            .init(id: "heights", title: "Head for heights", detail: "Visit 2 rooftops or viewpoints", symbol: "binoculars", earned: count(["rooftops", "viewpoints"]) >= 2),
            .init(id: "coffee", title: "Coffee snob", detail: "Visit 3 coffee spots", symbol: "cup.and.saucer", earned: count(["coffee"]) >= 3),
            .init(id: "culture", title: "Culture vulture", detail: "Visit 5 cultural or architectural sights", symbol: "building.columns", earned: count(["culture", "architecture"]) >= 5),
            .init(id: "starred", title: "Starred table", detail: "Dine at a Michelin-recognised restaurant", symbol: "fork.knife",
                  earned: visited.contains { !($0.awards ?? []).isEmpty }),
        ]
    }
}

extension AppEnvironment {
    var achievements: [Achievement] { Achievements.evaluate(visited: visitedPlaces) { [weak self] in self?.category(for: $0)?.slug } }

    /// Visited secrets in a city / all of them there.
    func progress(cityId: String?) -> (found: Int, total: Int) {
        guard let cityId else { return (0, 0) }
        return (visitedPlaces.filter { $0.cityId == cityId }.count, placeCounts[cityId] ?? 0)
    }
}
