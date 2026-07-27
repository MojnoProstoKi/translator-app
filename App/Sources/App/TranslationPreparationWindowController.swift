import AppKit
import SwiftUI
@preconcurrency import Translation

/// A small window whose only job is to host a `.translationTask` — the only way Apple's
/// `Translation` framework can present its own system download-consent UI and actually install
/// the on-device en→ru language pack. A plain, windowless `TranslationSession.prepareTranslation()`
/// call (what `AppleTranslationProvider` uses per-segment) cannot trigger that UI at all: it just
/// fails immediately with `LanguagePackNotInstalledError` if the pack isn't already present,
/// confirmed by manual testing — hence needing this separate, real window to anchor the download.
@MainActor
public final class TranslationPreparationWindowController: NSWindowController {
    public convenience init(
        source: Locale.Language,
        target: Locale.Language,
        onFinished: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "RealtimeTranslator"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: TranslationPreparationView(source: source, target: target, onFinished: onFinished)
        )
        self.init(window: window)
    }
}

private struct TranslationPreparationView: View {
    let source: Locale.Language
    let target: Locale.Language
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Загружается языковой пакет перевода (en → ru)…")
                .multilineTextAlignment(.center)
                .font(.callout)
        }
        .padding(24)
        .frame(width: 360, height: 130)
        .translationTask(source: source, target: target) { session in
            // Errors here (already installed elsewhere mid-flight, unsupported pairing, or the
            // user declining the download) all just mean this window has nothing more to do —
            // AppleTranslationProvider re-checks availability per segment and surfaces its own
            // `LanguagePackNotInstalledError` if the pack still isn't there.
            try? await session.prepareTranslation()
            onFinished()
        }
    }
}
