import SwiftUI
import AVFoundation
import Translation

// MARK: - Language Options

enum LangOption: String, CaseIterable, Identifiable, Hashable {
    case spanish = "es", french = "fr", german = "de", italian = "it"
    case portuguese = "pt", japanese = "ja", chinese = "zh-Hans"
    case korean = "ko", arabic = "ar", russian = "ru", turkish = "tr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spanish:    return "Spanish"
        case .french:     return "French"
        case .german:     return "German"
        case .italian:    return "Italian"
        case .portuguese: return "Portuguese"
        case .japanese:   return "Japanese"
        case .chinese:    return "Chinese"
        case .korean:     return "Korean"
        case .arabic:     return "Arabic"
        case .russian:    return "Russian"
        case .turkish:    return "Turkish"
        }
    }

    var flag: String {
        switch self {
        case .spanish:    return "🇪🇸"
        case .french:     return "🇫🇷"
        case .german:     return "🇩🇪"
        case .italian:    return "🇮🇹"
        case .portuguese: return "🇧🇷"
        case .japanese:   return "🇯🇵"
        case .chinese:    return "🇨🇳"
        case .korean:     return "🇰🇷"
        case .arabic:     return "🇸🇦"
        case .russian:    return "🇷🇺"
        case .turkish:    return "🇹🇷"
        }
    }

    // BCP-47 codes for AVSpeechSynthesisVoice
    var speechCode: String {
        switch self {
        case .spanish:    return "es-ES"
        case .french:     return "fr-FR"
        case .german:     return "de-DE"
        case .italian:    return "it-IT"
        case .portuguese: return "pt-BR"
        case .japanese:   return "ja-JP"
        case .chinese:    return "zh-CN"
        case .korean:     return "ko-KR"
        case .arabic:     return "ar-SA"
        case .russian:    return "ru-RU"
        case .turkish:    return "tr-TR"
        }
    }
}

// MARK: - Speech Player

private final class SpeechPlayer: ObservableObject {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, langCode: String) {
        guard !text.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: langCode)
        utterance.rate = 0.42
        synth.speak(utterance)
    }
}

// MARK: - Main View

@available(iOS 17.4, *)
struct LanguageLearnView: View {
    @StateObject private var classifier = ObjectClassifier()
    @StateObject private var speechPlayer = SpeechPlayer()

    @State private var targetLang = LangOption.spanish
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationSession: TranslationSession?
    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var isFrozen = false
    @State private var showLangPicker = false
    @State private var pulseActive = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen camera
            CameraPreview(session: classifier.captureSession)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { isFrozen.toggle() }
                }

            // Bottom gradient
            LinearGradient(
                colors: [.clear, Color.mSurface.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                scanStatus
                    .padding(.bottom, 14)
                detectionCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            classifier.start()
            setupTranslation()
            pulseActive = true
        }
        .onDisappear {
            classifier.stop()
        }
        .onChange(of: classifier.topLabel) {
            let label = classifier.topLabel
            guard !isFrozen, !label.isEmpty else { return }
            translate(label)
        }
        .onChange(of: targetLang) {
            translatedText = ""
            setupTranslation()
        }
        .translationTask(translationConfig) { session in
            await MainActor.run { self.translationSession = session }
            let word = classifier.topLabel
            guard !word.isEmpty else { return }
            await doTranslate(session: session, word: word)
        }
        .sheet(isPresented: $showLangPicker) {
            LangPickerSheet(selected: $targetLang)
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Language Learning")
                    .font(.mTitle(17))
                    .foregroundStyle(Color.mOnSurface)
                Text(isFrozen ? "Tap to resume scanning" : "Tap camera to freeze")
                    .font(.mLabel(11))
                    .foregroundStyle(Color.mSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            Spacer()
            Button { showLangPicker = true } label: {
                HStack(spacing: 5) {
                    Text("EN")
                        .font(.mLabel(12))
                        .foregroundStyle(Color.mSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.mSecondary)
                    Text(targetLang.flag)
                        .font(.system(size: 18))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.mSurfaceContainerHigh.opacity(0.85), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private var scanStatus: some View {
        HStack(spacing: 8) {
            ZStack {
                if !isFrozen {
                    Circle()
                        .stroke(Color.mSecondaryFixedDim.opacity(0.35), lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .scaleEffect(pulseActive ? 1.8 : 1.0)
                        .opacity(pulseActive ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                            value: pulseActive
                        )
                }
                Circle()
                    .fill(isFrozen ? Color.mSecondary : Color.mSecondaryFixedDim)
                    .frame(width: 8, height: 8)
            }
            Text(isFrozen ? "Frozen" : "Scanning")
                .font(.mLabel(11))
                .foregroundStyle(Color.mSecondary)
                .textCase(.uppercase)
                .tracking(1.2)
        }
    }

    @ViewBuilder
    private var detectionCard: some View {
        VStack(spacing: 0) {
            if classifier.topLabel.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(Color.mSecondary)
                    Text("Point camera at any object")
                        .font(.mBody())
                        .foregroundStyle(Color.mSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                // Detected (English)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DETECTED")
                            .font(.mLabel(10))
                            .foregroundStyle(Color.mSecondary)
                            .tracking(1.5)
                        Text(classifier.topLabel)
                            .font(.mTitle(20))
                            .foregroundStyle(Color.mOnSurface)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("🇬🇧")
                        .font(.system(size: 30))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Rectangle()
                    .fill(Color.mOutlineVariant)
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                // Translation
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(targetLang.displayName.uppercased())
                            .font(.mLabel(10))
                            .foregroundStyle(Color.mSecondary)
                            .tracking(1.5)
                        if isTranslating {
                            ProgressView()
                                .tint(Color.mPrimary)
                                .frame(height: 38)
                        } else {
                            Text(translatedText.isEmpty ? "—" : translatedText)
                                .font(.mDisplay(34))
                                .foregroundStyle(Color.mPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    Spacer()
                    VStack(spacing: 12) {
                        Text(targetLang.flag)
                            .font(.system(size: 30))
                        Button {
                            speechPlayer.speak(translatedText, langCode: targetLang.speechCode)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(translatedText.isEmpty ? Color.mSecondary : Color.mPrimary)
                                .frame(width: 46, height: 46)
                                .background(Color.mPrimaryContainer.opacity(translatedText.isEmpty ? 0.15 : 0.4), in: Circle())
                        }
                        .disabled(translatedText.isEmpty)
                        .animation(.easeInOut(duration: 0.2), value: translatedText.isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .glassCard(radius: 20)
        .ambientShadow()
        .animation(.easeInOut(duration: 0.3), value: classifier.topLabel.isEmpty)
    }

    // MARK: - Logic

    private func setupTranslation() {
        translationSession = nil
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: targetLang.rawValue)
        )
    }

    private func translate(_ word: String) {
        withAnimation { isTranslating = true }
        translatedText = ""
        guard let session = translationSession else { return }
        Task { @MainActor in
            await doTranslate(session: session, word: word)
        }
    }

    @MainActor
    private func doTranslate(session: TranslationSession, word: String) async {
        do {
            let response = try await session.translate(word)
            withAnimation { self.translatedText = response.targetText }
        } catch {}
        withAnimation { self.isTranslating = false }
    }
}

// MARK: - Language Picker Sheet

@available(iOS 17.4, *)
private struct LangPickerSheet: View {
    @Binding var selected: LangOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(LangOption.allCases, id: \.self) { lang in
                    Button {
                        selected = lang
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Text(lang.flag).font(.system(size: 26))
                            Text(lang.displayName)
                                .font(.mBody())
                                .foregroundStyle(Color.mOnSurface)
                            Spacer()
                            if lang == selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.mPrimary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.mSurfaceContainer)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.mSurface)
            .navigationTitle("Target Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.mPrimary)
                        .font(.mTitle(16))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
