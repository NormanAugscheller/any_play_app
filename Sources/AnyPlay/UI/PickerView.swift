// PickerView.swift — the window list.
//
// SwiftUI, because a list with four states would take several times the code in
// AppKit. The windows themselves (NSWindow, NSPanel, window levels) stay AppKit —
// that is where AnyPlay needs control SwiftUI does not give.

import SwiftUI
import AnyPlayKit

/// An 8-point grid as the base for all spacing.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
}

struct PickerView: View {
    @ObservedObject var registry: WindowRegistry
    @ObservedObject var selection: Selection
    let onSelect: (TargetWindow) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 280)
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Text(verbatim: L10n.tr("picker.title"))
                .font(.headline)
            Spacer()
            Button(action: onRefresh) {
                Label(L10n.tr("picker.reload"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L10n.tr("picker.reload.help"))
        }
        .padding(Space.m)
    }

    @ViewBuilder
    private var content: some View {
        switch registry.state {
        case .loading:
            StatusBox(systemImage: "hourglass",
                      title: L10n.tr("picker.loading"),
                      message: nil, actionTitle: nil, action: nil)

        case .failed(let message):
            StatusBox(systemImage: "exclamationmark.triangle.fill",
                      title: L10n.tr("picker.failed.title"),
                      message: message,
                      actionTitle: L10n.tr("picker.retry"),
                      action: onRefresh)

        case .ready(let windows) where windows.isEmpty:
            StatusBox(systemImage: "macwindow",
                      title: L10n.tr("picker.empty.title"),
                      message: L10n.tr("picker.empty.message"),
                      actionTitle: L10n.tr("picker.reload"),
                      action: onRefresh)

        case .ready(let windows):
            list(windows)
        }
    }

    private func list(_ windows: [TargetWindow]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups(of: windows), id: \.app) { group in
                    Text(verbatim: group.app)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Space.m)
                        .padding(.top, Space.m)
                        .padding(.bottom, Space.xs)
                    ForEach(group.windows) { window in
                        WindowRow(window: window,
                                  isSelected: selection.windowID == window.windowID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(window) }
                    }
                }
            }
            .padding(.bottom, Space.m)
        }
    }

    private func groups(of windows: [TargetWindow]) -> [(app: String, windows: [TargetWindow])] {
        var order: [String] = []
        var byApp: [String: [TargetWindow]] = [:]
        for window in windows {
            if byApp[window.appName] == nil { order.append(window.appName) }
            byApp[window.appName, default: []].append(window)
        }
        return order.map { ($0, byApp[$0] ?? []) }
    }
}

private struct WindowRow: View {
    let window: TargetWindow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            // Not colour alone: the checkmark carries the information.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "macwindow")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: window.displayTitle)
                    .lineLimit(1)
                HStack(spacing: Space.xs) {
                    Text(verbatim: window.sizeDescription)
                    if !window.isOnScreen {
                        Text(verbatim: L10n.tr("picker.notVisible"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(minHeight: 44)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}

/// Loading, empty and error state look alike and differ only in content.
struct StatusBox: View {
    let systemImage: String
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(verbatim: title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
