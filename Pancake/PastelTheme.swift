import SwiftUI

// MARK: - Pastel Color Palette

extension Color {
    // Primary pastel colors
    static let pastelLavender = Color(red: 0.71, green: 0.64, blue: 0.95)      // Soft purple
    static let pastelPeriwinkle = Color(red: 0.62, green: 0.68, blue: 0.97)    // Blue-purple
    static let pastelMint = Color(red: 0.60, green: 0.90, blue: 0.78)          // Soft green
    static let pastelCoral = Color(red: 0.98, green: 0.65, blue: 0.62)         // Soft red-orange
    static let pastelPeach = Color(red: 0.99, green: 0.78, blue: 0.65)         // Warm orange
    static let pastelSky = Color(red: 0.60, green: 0.82, blue: 0.98)           // Soft blue
    static let pastelRose = Color(red: 0.96, green: 0.65, blue: 0.76)          // Soft pink
    static let pastelLemon = Color(red: 0.98, green: 0.92, blue: 0.60)         // Soft yellow
    static let pastelLilac = Color(red: 0.82, green: 0.72, blue: 0.96)         // Light purple

    // Card and background tints
    static let pastelCardBackground = Color(red: 0.96, green: 0.95, blue: 1.0) // Very light lavender
    static let pastelGroupedBackground = Color(red: 0.97, green: 0.96, blue: 1.0)
    static var pancakeSystemBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.systemBackground)
#endif
    }

    static var pancakeSystemGray6: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(.systemGray6)
#endif
    }

    // Intensity colors (pastel versions)
    static let pastelEasy = Color(red: 0.60, green: 0.90, blue: 0.78)          // Mint
    static let pastelMedium = Color(red: 0.99, green: 0.78, blue: 0.65)        // Peach
    static let pastelHard = Color(red: 0.98, green: 0.65, blue: 0.62)          // Coral
}

// MARK: - Pastel Gradients

extension LinearGradient {
    static let pastelPrimary = LinearGradient(
        colors: [.pastelLavender, .pastelPeriwinkle],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pastelAccent = LinearGradient(
        colors: [.pastelPeriwinkle, .pastelSky],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pastelWarm = LinearGradient(
        colors: [.pastelPeach, .pastelCoral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pastelCool = LinearGradient(
        colors: [.pastelMint, .pastelSky],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pastelStart = LinearGradient(
        colors: [.pastelMint, Color(red: 0.50, green: 0.85, blue: 0.70)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pastelProfile = LinearGradient(
        colors: [.pastelLavender, .pastelRose],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Bubbly Button Style

struct BubblyButtonStyle: ButtonStyle {
    let backgroundColor: Color
    let foregroundColor: Color

    init(backgroundColor: Color = .pastelLavender, foregroundColor: Color = .white) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(foregroundColor)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .shadow(color: backgroundColor.opacity(0.4), radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct BubblyGradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient

    init(gradient: LinearGradient = .pastelPrimary) {
        self.gradient = gradient
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(gradient)
                    .shadow(color: Color.pastelLavender.opacity(0.4), radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Bubbly Card Modifier

struct BubblyCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.pancakeSystemBackground)
                    .shadow(color: Color.pastelLavender.opacity(0.18), radius: 8, x: 0, y: 4)
            )
    }
}

extension View {
    func bubblyCard(padding: CGFloat = 16) -> some View {
        modifier(BubblyCardModifier(padding: padding))
    }
}

// MARK: - Pastel Tinted Card Modifier

struct PastelTintedCardModifier: ViewModifier {
    let tintColor: Color

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tintColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(tintColor.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func pastelTintedCard(_ tintColor: Color = .pastelLavender) -> some View {
        modifier(PastelTintedCardModifier(tintColor: tintColor))
    }
}

// MARK: - Bubbly Small Button Style (for inline/small buttons)

struct BubblySmallButtonStyle: ButtonStyle {
    let backgroundColor: Color

    init(backgroundColor: Color = .pastelPeriwinkle) {
        self.backgroundColor = backgroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .shadow(color: backgroundColor.opacity(0.3), radius: configuration.isPressed ? 1 : 4, x: 0, y: configuration.isPressed ? 0 : 2)
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Pastel Tag Style (for toggleable chips like Time/Distance)

struct PastelTagStyle: ViewModifier {
    let isSelected: Bool
    let activeColor: Color

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.medium)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(isSelected ? activeColor.opacity(0.2) : Color.pancakeSystemGray6)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? activeColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isSelected ? activeColor : .primary)
    }
}

extension View {
    func pastelTag(isSelected: Bool, activeColor: Color = .pastelLavender) -> some View {
        modifier(PastelTagStyle(isSelected: isSelected, activeColor: activeColor))
    }
}

// MARK: - Intensity Color Helper

extension Intensity {
    var pastelColor: Color {
        switch self {
        case .zone1: return .pastelSky
        case .zone2: return .pastelMint
        case .zone3: return .pastelLemon
        case .zone4: return .pastelPeach
        case .zone5: return .pastelCoral
        }
    }
}
