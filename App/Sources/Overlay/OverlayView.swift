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
            // Always visible during a session: lets the user see *when* to start speaking/play
            // audio instead of guessing (requested explicitly) — audio capture starts as soon
            // as the session does, even while recognition/translation assets are still being
            // checked, so this reacts before "Подготовка…"/lines do.
            LevelMeterView(level: viewModel.audioLevel)
                .frame(height: 18)
                .padding(.bottom, 2)

            if let errorText = viewModel.errorBannerText {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorText)
                        .font(.system(size: 13, weight: .medium))
                }
            } else if viewModel.isPreparing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Подготовка… при первом запуске загрузка языковой модели может занять до минуты")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.lines.isEmpty {
                Text("Слушаю…")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.lines) { line in
                    lineView(line)
                }
            }
            // Always-visible diagnostic: makes "zero events received" impossible to mistake for
            // "events received but with empty text" without opening Console — requested after a
            // report of empty-looking output that turned out ambiguous to diagnose remotely.
            Text("событий получено: \(viewModel.eventCount)")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(line.originalText.isEmpty ? "[EN: пусто]" : line.originalText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .italic(!line.isFinal)
            Text(line.translatedText.isEmpty ? "[RU: пусто]" : line.translatedText)
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

/// A small equalizer-style live level meter: a row of bars whose heights react to the current
/// captured-audio peak level, so it's visually obvious *when* speech/audio is actually reaching
/// the app (as opposed to silence) — independent of whether recognition/translation have
/// produced anything yet.
private struct LevelMeterView: View {
    let level: Float

    /// Relative height multipliers per bar, purely cosmetic (no per-band frequency data is
    /// available — this is amplitude only) so the meter doesn't look like one flat block.
    private static let barMultipliers: [CGFloat] = [0.5, 0.85, 1.0, 0.7, 0.4]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(Self.barMultipliers.enumerated()), id: \.offset) { _, multiplier in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor)
                    .frame(width: 4, height: barHeight(multiplier))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(_ multiplier: CGFloat) -> CGFloat {
        let clampedLevel = CGFloat(max(0, min(1, level)))
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 18
        return minHeight + (maxHeight - minHeight) * clampedLevel * multiplier
    }

    private var barColor: Color {
        level > 0.05 ? .green : .secondary.opacity(0.4)
    }
}
