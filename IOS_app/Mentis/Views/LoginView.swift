import SwiftUI

// MARK: - Particle Background

private struct ParticleParam {
    let x0, y0: CGFloat
    let vx, vy: CGFloat
    let bobAmp, bobFreq, bobPhase: CGFloat
    let size: CGFloat
}

private struct ShapeParam {
    let cx0, cy0: CGFloat
    let vx, vy: CGFloat
    let radius: CGFloat
    let sides: Int
    let rotSpeed: CGFloat
    let rotPhase: CGFloat
    let opacity: Double
}

private struct ParticlesBg: View {
    private let particles: [ParticleParam]
    private let shapes: [ShapeParam]

    init() {
        var rng = SystemRandomNumberGenerator()
        var ps: [ParticleParam] = []
        for _ in 0..<70 {
            ps.append(ParticleParam(
                x0:       .random(in: 0...1, using: &rng),
                y0:       .random(in: 0...1, using: &rng),
                vx:       .random(in: -0.009...0.009, using: &rng),
                vy:       .random(in: -0.007...0.007, using: &rng),
                bobAmp:   .random(in: 0.006...0.018, using: &rng),
                bobFreq:  .random(in: 0.25...0.80, using: &rng),
                bobPhase: .random(in: 0...(2 * .pi), using: &rng),
                size:     .random(in: 2.0...4.0, using: &rng)
            ))
        }
        particles = ps

        var ss: [ShapeParam] = []
        for _ in 0..<7 {
            let sign: CGFloat = Bool.random(using: &rng) ? 1 : -1
            ss.append(ShapeParam(
                cx0:      .random(in: 0.05...0.95, using: &rng),
                cy0:      .random(in: 0.05...0.95, using: &rng),
                vx:       .random(in: -0.004...0.004, using: &rng),
                vy:       .random(in: -0.003...0.003, using: &rng),
                radius:   .random(in: 0.05...0.11, using: &rng),
                sides:    Bool.random(using: &rng) ? 3 : 6,
                rotSpeed: .random(in: 0.12...0.40, using: &rng) * sign,
                rotPhase: .random(in: 0...(2 * .pi), using: &rng),
                opacity:  .random(in: 0.07...0.18, using: &rng)
            ))
        }
        shapes = ss
    }

    var body: some View {
        TimelineView(.animation) { (ctx: TimelineViewDefaultContext) in
            let t = CGFloat(ctx.date.timeIntervalSinceReferenceDate)
            Canvas { (context: inout GraphicsContext, size: CGSize) in
                func wx(_ x0: CGFloat, _ vx: CGFloat) -> CGFloat {
                    let v = x0 + vx * t
                    let r = v.truncatingRemainder(dividingBy: 1)
                    return (r < 0 ? r + 1 : r) * size.width
                }
                func wy(_ y0: CGFloat, _ vy: CGFloat,
                        _ amp: CGFloat, _ freq: CGFloat, _ phase: CGFloat) -> CGFloat {
                    let v = y0 + vy * t + amp * sin(freq * t + phase)
                    let r = v.truncatingRemainder(dividingBy: 1)
                    return (r < 0 ? r + 1 : r) * size.height
                }

                let positions: [CGPoint] = particles.map { p in
                    CGPoint(x: wx(p.x0, p.vx),
                            y: wy(p.y0, p.vy, p.bobAmp, p.bobFreq, p.bobPhase))
                }

                // Connection lines
                let thresh2 = (size.width * 0.17) * (size.width * 0.17)
                var lines = Path()
                for i in 0..<positions.count {
                    for j in (i + 1)..<positions.count {
                        let dx = positions[i].x - positions[j].x
                        let dy = positions[i].y - positions[j].y
                        if dx * dx + dy * dy < thresh2 {
                            lines.move(to: positions[i])
                            lines.addLine(to: positions[j])
                        }
                    }
                }
                context.stroke(lines,
                               with: .color(.init(hex: "#3a4088").opacity(0.30)),
                               lineWidth: 0.65)

                // Dots
                for (i, pos) in positions.enumerated() {
                    let r = particles[i].size / 2
                    context.fill(
                        Path(ellipseIn: .init(x: pos.x - r, y: pos.y - r,
                                              width: particles[i].size,
                                              height: particles[i].size)),
                        with: .color(.init(hex: "#818cf8").opacity(0.78))
                    )
                }

                // Rotating polygons
                let dim = min(size.width, size.height)
                for s in shapes {
                    let cx = wx(s.cx0, s.vx)
                    let cy = wy(s.cy0, s.vy, 0, 0, 0)
                    let r  = s.radius * dim
                    let angle = s.rotSpeed * t + s.rotPhase
                    var poly = Path()
                    for k in 0..<s.sides {
                        let a  = angle + CGFloat(k) * (.pi * 2) / CGFloat(s.sides)
                        let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                        if k == 0 { poly.move(to: pt) } else { poly.addLine(to: pt) }
                    }
                    poly.closeSubpath()
                    context.stroke(poly,
                                   with: .color(.init(hex: "#66d9cc").opacity(s.opacity)),
                                   lineWidth: 1.0)
                }
            }
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email        = ""
    @State private var isLoading    = false
    @State private var errorMessage: String?
    @State private var showSettings = false

    private let titleGradient = LinearGradient(
        colors: [Color(hex: "#dee0ff"), Color.mPrimary, Color.mSecondaryFixedDim],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            // ── Full-screen background ──────────────────────────────────────
            Color(hex: "#06080f").ignoresSafeArea()
            ParticlesBg().ignoresSafeArea()

            // Vignette
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.50)],
                center: .center,
                startRadius: 140,
                endRadius: 500
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Settings gear — top right
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.mSecondary)
                            .padding(20)
                    }
                }

                Spacer().frame(maxHeight: 60)

                // ── Title + Form centered together ───────────────────────────
                VStack(spacing: 36) {
                    VStack(spacing: 10) {
                        Text("MENTIS")
                            .font(.mDisplay(58))
                            .tracking(-1)
                            .foregroundStyle(titleGradient)
                            .shadow(color: Color.mPrimary.opacity(0.55),
                                    radius: 28, x: 0, y: 0)

                        Text("Your spatial memory palace")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(3.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.mSecondary)
                    }

                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL")
                                .font(.mLabel())
                                .tracking(0.8)
                                .foregroundStyle(Color.mSecondary)
                            TextField("", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .textContentType(.emailAddress)
                                .sinkStyle()
                        }

                        if let err = errorMessage {
                            Text(err)
                                .font(.mLabel())
                                .foregroundStyle(Color(hex: "#ff6b8a"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        MentisPrimaryButton(title: "Continue", isLoading: isLoading) {
                            Task { await login() }
                        }
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                        .opacity(email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: "#10141a"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color(hex: "#454652").opacity(0.35), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            ServerSettingsSheet()
        }
    }

    private func login() async {
        isLoading    = true
        errorMessage = nil
        do {
            let resp = try await APIClient.shared.login(email: email)
            appState.login(userId: resp.user_id, email: resp.email)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Server Settings Sheet

private struct ServerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url: String = APIClient.shared.baseURL

    var body: some View {
        ZStack {
            Color.mSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("Server Settings")
                    .font(.mTitle(22))
                    .foregroundStyle(Color.mOnSurface)

                VStack(alignment: .leading, spacing: 6) {
                    Text("SERVER URL")
                        .font(.mLabel())
                        .tracking(0.8)
                        .foregroundStyle(Color.mSecondary)
                    TextField("http://10.0.0.147:5001", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .sinkStyle()
                }

                Text("Use your Mac's LAN IP when running on a real device. Find it with: ipconfig getifaddr en0")
                    .font(.mLabel(12))
                    .foregroundStyle(Color.mSecondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                MentisPrimaryButton(title: "Save", isLoading: false) {
                    APIClient.shared.baseURL = url
                    dismiss()
                }

                Spacer()
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
