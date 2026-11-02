import SwiftUI

/// Animierter Startbildschirm im App-Thema: Bordeaux-Verlauf, Weinglas,
/// „SondiNetwork Weinkeller“. Wird von `ContentView` über die Tabs gelegt
/// und nach kurzer Zeit ausgeblendet.
struct SplashView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var glassVisible = false
    @State private var titleVisible = false
    @State private var glowPhase = false

    static let displayDuration: Duration = .seconds(1.9)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 28) {
                glass
                title
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea()
        .onAppear(perform: startAnimation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SondiNetwork Weinkeller")
    }

    // MARK: Hintergrund

    private var background: some View {
        ZStack {
            Brand.gradient

            // Sanftes Licht, das langsam atmet
            RadialGradient(
                colors: [Color(red: 1, green: 0.85, blue: 0.7).opacity(0.28), .clear],
                center: .init(x: 0.3, y: 0.25),
                startRadius: 0,
                endRadius: glowPhase ? 420 : 340
            )
        }
    }

    // MARK: Glas

    private var glass: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 168, height: 168)
                .blur(radius: 2)
            Circle()
                .strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: 168, height: 168)
            Image(systemName: "wineglass.fill")
                .font(.system(size: 78, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.98, green: 0.85, blue: 0.62)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }
        .scaleEffect(glassVisible ? 1 : 0.6)
        .opacity(glassVisible ? 1 : 0)
    }

    // MARK: Titel

    private var title: some View {
        VStack(spacing: 6) {
            Text("SondiNetwork")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .tracking(4)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.75))
            Text("Wyychällerli")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .opacity(titleVisible ? 1 : 0)
        .offset(y: titleVisible ? 0 : 14)
    }

    // MARK: Animation

    private func startAnimation() {
        guard !reduceMotion else {
            glassVisible = true
            titleVisible = true
            return
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
            glassVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.35)) {
            titleVisible = true
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            glowPhase = true
        }
    }
}

#Preview {
    SplashView()
}
