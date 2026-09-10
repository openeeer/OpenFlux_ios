import SwiftUI

// MARK: - Design tokens

extension Color {
    // Surfaces
    static let glassBase        = Color(red: 0.08, green: 0.09, blue: 0.12)
    static let glassSurface     = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let glassRaised      = Color(red: 0.17, green: 0.19, blue: 0.24)
    static let glassBorder      = Color(white: 1.0).opacity(0.10)
    static let glassBorderBright = Color(white: 1.0).opacity(0.18)

    // Text
    static let textPrimary      = Color(white: 0.97)
    static let textSecondary    = Color(white: 0.60)
    static let textMuted        = Color(white: 0.38)

    // Accent – electric indigo
    static let accentCore       = Color(red: 0.38, green: 0.44, blue: 1.00)
    static let accentGlow       = Color(red: 0.38, green: 0.44, blue: 1.00).opacity(0.28)
    static let accentMuted      = Color(red: 0.38, green: 0.44, blue: 1.00).opacity(0.15)

    // Semantic
    static let success          = Color(red: 0.24, green: 0.82, blue: 0.56)
    static let warning          = Color(red: 1.00, green: 0.75, blue: 0.20)
    static let danger           = Color(red: 1.00, green: 0.36, blue: 0.36)
}

// MARK: - Liquid Glass card modifier

struct LiquidGlassCard: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    Color.glassSurface
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 6)
    }
}

struct LiquidGlassInner: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.glassRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
    }
}

extension View {
    func liquidGlassCard(padding: CGFloat = 20) -> some View {
        modifier(LiquidGlassCard(padding: padding))
    }
    func liquidGlassInner() -> some View {
        modifier(LiquidGlassInner())
    }
}

// MARK: - Animated gradient background

struct AnimatedBackground: View {
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Color.glassBase.ignoresSafeArea()

            // Blob 1
            Circle()
                .fill(Color.accentCore.opacity(0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(
                    x: -80 + CGFloat(sin(phase) * 30),
                    y: -200 + CGFloat(cos(phase * 0.7) * 20)
                )

            // Blob 2
            Circle()
                .fill(Color(red: 0.55, green: 0.22, blue: 0.90).opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(
                    x: 100 + CGFloat(cos(phase * 0.9) * 25),
                    y: 180 + CGFloat(sin(phase * 1.1) * 18)
                )

            // Blob 3 – subtle teal
            Circle()
                .fill(Color(red: 0.10, green: 0.75, blue: 0.70).opacity(0.10))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(
                    x: CGFloat(sin(phase * 1.3) * 40),
                    y: CGFloat(cos(phase * 0.6) * 50)
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let status: ConnectionStatus

    var color: Color {
        switch status {
        case .connected:    return .success
        case .connecting:   return .warning
        case .disconnected: return .textMuted
        case .error:        return .danger
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle().stroke(color.opacity(0.4), lineWidth: 4)
                        .scaleEffect(status == .connected ? 1.6 : 1)
                        .opacity(status == .connected ? 0 : 1)
                        .animation(
                            status == .connected
                                ? .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                                : .default,
                            value: status == .connected
                        )
                )

            Text(status.displayText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Primary action button

struct PrimaryButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pressed = false }
            }
            action()
        }) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        color
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.45), radius: pressed ? 4 : 14, x: 0, y: pressed ? 2 : 7)
                .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let label: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.textSecondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassInner()
    }
}
