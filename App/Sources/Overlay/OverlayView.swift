import SwiftUI
import TranslationEngine

/// The floating overlay's content (FR-009): a small, translucent panel showing the live
/// Russian translation as it streams in, with partial (in-progress) text visually distinct from
/// finalized text.
public struct OverlayView: View {
    @ObservedObject private var viewModel: OverlayViewModel

    public init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let consentText = viewModel.consentBannerText {
                Text(consentText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
            }

            // Scrollable so a longer session's history (more lines than fit the panel) stays
            // reachable instead of only ever showing the last few — the panel is also resizable
            // (deeper by default now) so there's more room before scrolling is even needed.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if let errorText = viewModel.errorBannerText {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(errorText)
                                    .font(.system(size: 13, weight: .medium))
                            }
                        } else if viewModel.lines.isEmpty {
                            Text("Слушаю…")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.lines) { line in
                                lineView(line).id(line.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.lines) { _, lines in
                    guard let lastId = lines.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)

            // Pinned to the bottom (below the scrollable transcript) so it's always visible
            // without scrolling — lets the user see *when* to start speaking/play audio instead
            // of guessing (requested explicitly).
            LevelMeterView(level: viewModel.audioLevel)
                .frame(height: 18)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func lineView(_ line: OverlayLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if viewModel.showsSourceLabels {
                Text(sourceLabel(line.sourceType))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }
            // English (recognized) shown above Russian (translated) so it's visible at a
            // glance whether recognition or translation is the one not working. Placeholders
            // are spelled out (not "…") so a screenshot unambiguously shows "empty" rather than
            // something that could be misread as literal punctuation in the recognized text.
            Text(line.originalText.isEmpty ? "[\(viewModel.direction.originalLanguageLabel): пусто]" : line.originalText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .italic(!line.isFinal)
            Text(line.translatedText.isEmpty ? "[\(viewModel.direction.translatedLanguageLabel): пусто]" : line.translatedText)
                .font(.system(size: 16, weight: line.isFinal ? .semibold : .regular))
                .foregroundStyle(line.isFinal ? .primary : .secondary)
                .italic(!line.isFinal)
        }
    }

    private func sourceLabel(_ sourceType: AudioSourceType) -> String {
        switch sourceType {
        case .microphone: return "Микрофон"
        case .systemAudio: return "Системный звук"
        }
    }
}

/// A native SF Symbol waveform indicator, so it's visually obvious *when* speech/audio is
/// actually reaching the app (as opposed to silence) — independent of whether
/// recognition/translation have produced anything yet. Uses the system's own
/// `.variableColor.iterative` symbol effect (the same style as Siri/dictation) rather than a
/// custom-drawn bar meter, so it animates and looks native for free.
private struct LevelMeterView: View {
    /// Raw linear peak amplitude (0...1) from the capture source.
    let level: Float

    /// Converts the linear peak to a perceptual (dB-based) 0...1 scale before deciding
    /// activity/animation — human hearing (and speech loudness) is logarithmic, so quiet-but-
    /// intelligible speech (the kind ASR/translation already handles fine) sits at a linear peak
    /// as low as ~0.01–0.03, far under any reasonable *linear* threshold. Confirmed by manual
    /// testing: the old linear threshold only reacted to noticeably loud speech, while text kept
    /// translating normally for quiet speech the whole time.
    private var perceivedLevel: Float {
        guard level > 0.0001 else { return 0 }
        let decibels = 20 * log10(level)
        let floorDecibels: Float = -50
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }

    private var isActive: Bool { perceivedLevel > 0.08 }

    var body: some View {
        Image(systemName: "waveform")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(isActive ? Color.green : Color.secondary.opacity(0.5))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
            .scaleEffect(1 + CGFloat(perceivedLevel) * 0.2, anchor: .center)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .animation(.easeOut(duration: 0.15), value: isActive)
    }
}


