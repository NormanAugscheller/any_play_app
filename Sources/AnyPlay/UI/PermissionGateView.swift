// PermissionGateView.swift — what is shown while a permission is missing.
//
// A missing permission must never lead to a silent black picture. So AnyPlay does not
// even show the window list while Screen Recording is missing.

import SwiftUI

struct PermissionGateView: View {
    let permission: Permission
    /// Becomes true once the permission is granted — then only a restart helps.
    @Binding var grantedNeedsRestart: Bool
    let onOpenSettings: () -> Void
    let onRequest: () -> Void
    let onRelaunch: () -> Void

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: grantedNeedsRestart ? "checkmark.circle.fill" : "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(grantedNeedsRestart ? Color.green : Color.secondary)

            Text(verbatim: grantedNeedsRestart
                 ? L10n.tr("gate.granted.title")
                 : L10n.tr("gate.needs.title", permission.title))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(verbatim: grantedNeedsRestart ? L10n.tr("gate.granted.message") : permission.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            if grantedNeedsRestart {
                Button(L10n.tr("gate.restart"), action: onRelaunch)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                VStack(spacing: Space.s) {
                    Button(L10n.tr("gate.openSettings"), action: onOpenSettings)
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                    Text(verbatim: L10n.tr("gate.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .onAppear(perform: onRequest)
            }
        }
        .padding(Space.l)
        .frame(minWidth: 520, minHeight: 360, maxHeight: .infinity)
    }
}
