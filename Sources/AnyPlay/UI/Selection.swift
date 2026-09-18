import CoreGraphics
import Combine
import AnyPlayKit

/// Which window is chosen. Deliberately its own small type and not a field of the
/// registry: the registry knows which windows exist, the choice is the user's.
@MainActor
final class Selection: ObservableObject {
    @Published var windowID: CGWindowID?
    @Published var identity: WindowIdentity?

    func set(_ window: TargetWindow) {
        windowID = window.windowID
        identity = window.identity
    }

    func clear() {
        windowID = nil
        identity = nil
    }
}
