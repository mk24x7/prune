import SwiftUI

/// Maps the 12 palette tokens from artifacts.json to SwiftUI colours.
enum Palette {
    static let colors: [String: Color] = [
        "green": .green,
        "mint": .mint,
        "orange": .orange,
        "red": .red,
        "brown": .brown,
        "yellow": .yellow,
        "teal": .teal,
        "blue": .blue,
        "purple": .purple,
        "cyan": .cyan,
        "pink": .pink,
        "gray": .gray,
    ]

    static func color(_ token: String?) -> Color {
        token.flatMap { colors[$0] } ?? .gray
    }
}
