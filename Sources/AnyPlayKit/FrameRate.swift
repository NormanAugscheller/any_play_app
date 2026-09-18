// FrameRate.swift — what a measured frame rate means for the person watching.

/// ScreenCaptureKit only delivers a frame when something changed, so a low rate can
/// simply mean a still picture. But measured during development: a fully covered
/// source drops from 57 to 15 frames per second, and a window in a hidden fullscreen
/// Space to 1. That deserves a word in the interface instead of a stuttering image.
public enum FrameRateVerdict: Equatable, Sendable {
    case idle        // nothing arrives — usually a still picture
    case stalled     // 1–2 per second: the source has nearly stopped drawing
    case throttled   // 3–19 per second: noticeably held back
    case healthy

    public static func classify(framesPerSecond fps: Int) -> FrameRateVerdict {
        switch fps {
        case ..<1:    return .idle
        case 1...2:   return .stalled
        case 3...19:  return .throttled
        default:      return .healthy
        }
    }
}
