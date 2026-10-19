import SwiftUI

enum GlowTheme {
    static let background = Color(red: 0.060, green: 0.086, blue: 0.071)
    static let card = Color(red: 0.105, green: 0.145, blue: 0.119)
    static let lime = Color(red: 0.84, green: 0.93, blue: 0.63)
    static let ink = Color(red: 0.94, green: 0.95, blue: 0.88)
    static let muted = Color(red: 0.62, green: 0.69, blue: 0.62)
    static let line = Color.white.opacity(0.10)
}

struct ConnectionBadge: View {
    let connected: Bool
    var busy = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(busy ? .orange : connected ? GlowTheme.lime : GlowTheme.muted).frame(width: 6, height: 6)
            Text(busy ? "Connecting" : connected ? "Connected" : "Offline")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(connected ? GlowTheme.lime : GlowTheme.muted)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.white.opacity(0.04), in: Capsule())
    }
}

struct RoundControl: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.055), in: Circle())
                .overlay(Circle().strokeBorder(GlowTheme.line))
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

struct CardContainer<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(22)
            .background(GlowTheme.card.gradient, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(GlowTheme.line))
    }
}
