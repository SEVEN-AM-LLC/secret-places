import SwiftUI

// MARK: - Typography

extension Theme {
    /// Display face for titles: the modern system sans (SF Pro), bold and tight. Never serif.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Category identity

/// Each category gets its own colour pair and symbol, so a screen of secrets reads at a glance.
struct CategoryStyle {
    let symbol: String
    /// Deep background for art and chips.
    let deep: Color
    /// Bright foreground on `deep`.
    let tint: Color

    static func of(_ slug: String?) -> CategoryStyle {
        switch slug {
        case "bars":          return .init(symbol: "wineglass", deep: rgb(0x4B1528), tint: rgb(0xED93B1))
        case "night":         return .init(symbol: "moon.stars", deep: rgb(0x26215C), tint: rgb(0xAFA9EC))
        case "rooftops":      return .init(symbol: "building.2", deep: rgb(0x3C3489), tint: rgb(0xCECBF6))
        case "food_drink":    return .init(symbol: "fork.knife", deep: rgb(0x712B13), tint: rgb(0xF5C4B3))
        case "coffee":        return .init(symbol: "cup.and.saucer", deep: rgb(0x633806), tint: rgb(0xFAC775))
        case "viewpoints":    return .init(symbol: "binoculars", deep: rgb(0x0C447C), tint: rgb(0x85B7EB))
        case "architecture":  return .init(symbol: "building.columns", deep: rgb(0x444441), tint: rgb(0xD3D1C7))
        case "culture":       return .init(symbol: "theatermasks", deep: rgb(0x72243E), tint: rgb(0xF4C0D1))
        case "walks":         return .init(symbol: "figure.walk", deep: rgb(0x27500A), tint: rgb(0xC0DD97))
        case "nature":        return .init(symbol: "leaf", deep: rgb(0x085041), tint: rgb(0x9FE1CB))
        case "beaches":       return .init(symbol: "beach.umbrella", deep: rgb(0x085041), tint: rgb(0x5DCAA5))
        case "underground":   return .init(symbol: "waveform", deep: rgb(0x2C2C2A), tint: rgb(0xB4B2A9))
        case "date_spots":    return .init(symbol: "heart", deep: rgb(0x72243E), tint: rgb(0xED93B1))
        default:              return .init(symbol: "sparkles", deep: rgb(0x412402), tint: Theme.accent)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension AppEnvironment {
    func style(forCategory id: String?) -> CategoryStyle { CategoryStyle.of(category(for: id)?.slug) }
}

// MARK: - Secret numbers

/// A stable two-digit "secret number" per place ("No. 07") — part of the collectible feel.
/// FNV-1a over the id, because Swift's Hasher is reseeded on every launch.
enum SecretNumber {
    static func of(_ id: String) -> Int {
        var h: UInt32 = 2_166_136_261
        for b in id.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return Int(h % 99) + 1
    }
    static func label(_ id: String) -> String { String(format: "No. %02d", of(id)) }
}

// MARK: - Mystery art

/// Cover for a place we can't (locked) or don't (no photo) show: the category's colours,
/// a quiet ring pattern, the category symbol and the secret's number. Never a photo of somewhere else.
struct MysteryArt: View {
    let style: CategoryStyle
    let seed: String
    var height: CGFloat = 150
    var locked: Bool = true

    var body: some View {
        ZStack {
            style.deep
            Canvas { ctx, size in
                // Concentric rings off-centre, position varies per place so a grid doesn't look stamped.
                let n = Double(SecretNumber.of(seed))
                let c = CGPoint(x: size.width * (0.25 + 0.5 * (n.truncatingRemainder(dividingBy: 7) / 7)),
                                y: size.height * (0.3 + 0.4 * (n.truncatingRemainder(dividingBy: 5) / 5)))
                for i in 1...7 {
                    let r = CGFloat(i) * max(size.width, size.height) * 0.11
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(style.tint.opacity(0.10 - Double(i) * 0.008)), lineWidth: 1)
                }
            }
            Image(systemName: style.symbol)
                .font(.system(size: height * 0.32, weight: .light))
                .foregroundStyle(style.tint)
                .shadow(color: style.tint.opacity(0.35), radius: 14)
        }
        .overlay(alignment: .bottomLeading) {
            Text(SecretNumber.label(seed))
                .font(Theme.display(13, weight: .semibold))
                .foregroundStyle(style.tint.opacity(0.85))
                .padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            if locked {
                Image(systemName: "lock.fill").font(.caption2.weight(.bold))
                    .foregroundStyle(style.tint.opacity(0.85)).padding(10)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    let category: Category
    var body: some View {
        let s = CategoryStyle.of(category.slug)
        HStack(spacing: 6) {
            Image(systemName: category.icon ?? s.symbol)
            Text(category.title)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(s.deep.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(s.tint.opacity(0.25), lineWidth: 1))
        .foregroundStyle(s.tint)
    }
}

// MARK: - Haptics

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}
