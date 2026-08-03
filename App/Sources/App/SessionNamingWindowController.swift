import AppKit
import SwiftUI

/// Shown right after a session ends, before it's saved — lets the user name it, pre-filled with
/// a sensible default (FR-012) so confirming immediately (Return, or the button) just keeps that
/// default; no separate "skip" path is needed.
@MainActor
public final class SessionNamingWindowController: NSWindowController {
    public convenience init(defaultTitle: String, onSave: @escaping (String) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Сохранить сессию"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentView = NSHostingView(
            rootView: SessionNamingView(defaultTitle: defaultTitle) { [weak window] title in
                onSave(title)
                window?.close()
            }
        )
        window.makeFirstResponder(window.contentView)
    }
}

private struct SessionNamingView: View {
    let defaultTitle: String
    let onSave: (String) -> Void

    @State private var title: String
    @FocusState private var isTitleFocused: Bool

    init(defaultTitle: String, onSave: @escaping (String) -> Void) {
        self.defaultTitle = defaultTitle
        self.onSave = onSave
        _title = State(initialValue: defaultTitle)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Название сессии")
                .font(.headline)
            TextField("Название", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit(save)
            Button("Сохранить", action: save)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360, height: 140)
        .onAppear { isTitleFocused = true }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? defaultTitle : trimmed)
    }
}
