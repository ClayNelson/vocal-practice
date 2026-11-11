import SwiftUI

/// Studio colors, matching the Mesmerize logo and icon: warm cream, black, and antique gold.
/// Each has a dark-mode variant in the asset catalog.
extension Color {
    /// Accent for icons, highlights, and links.
    static let gold = Color("Gold")
    /// Primary buttons (black in light mode, cream in dark).
    static let ink = Color("Ink")
    /// Text and icons on ink.
    static let onInk = Color("OnInk")
    /// Screen background behind lists and forms.
    static let canvas = Color("Canvas")
}

extension ShapeStyle where Self == Color {
    static var gold: Color { .gold }
    static var ink: Color { .ink }
}

/// A Form on the cream canvas. Use in place of Form for full screens.
struct CanvasForm<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content }.scrollContentBackground(.hidden).background(Color.canvas)
    }
}

/// A List on the cream canvas. Use in place of List for full screens.
struct CanvasList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        List { content }.scrollContentBackground(.hidden).background(Color.canvas)
    }
}
