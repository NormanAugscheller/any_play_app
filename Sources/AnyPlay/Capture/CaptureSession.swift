// CaptureSession.swift — mirroring one window live.
//
// The path from frame to picture has no copy: the IOSurface is taken out of the
// CMSampleBuffer and attached directly to CALayer.contents. Going through NSImage
// would push every frame through main memory once.

import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreImage
import AnyPlayKit

struct CaptureSettings {
    var maximumFPS: Int = 60
    var showsCursor: Bool = false
    /// Three buffers: enough that a short hiccup drops nothing, few enough to add no lag.
    var queueDepth: Int = 3
}

@MainActor
final class CaptureSession: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Measured frame rate. A covered source can drop to 15 or even 1 frame per second;
    /// that has to be visible rather than passed on as a stuttering picture.
    @Published private(set) var framesPerSecond: Int = 0
    @Published private(set) var lastFrameStatus: SCFrameStatus?
    /// Frames per second whose picture actually differs from the one before.
    ///
    /// `framesPerSecond` counts what ScreenCaptureKit delivers, which is not the same
    /// thing: a window that has stopped drawing can still produce a full stream of
    /// identical frames. Only this number says whether the picture is alive.
    @Published private(set) var changedFramesPerSecond: Int = 0
    /// Stream resolution in real pixels — the number that shows whether a Retina
    /// display is mirrored sharply.
    @Published private(set) var pixelSize: CGSize = .zero

    /// Consumers of finished frames — the preview window and every overlay is one.
    /// A list rather than a single closure, or only one place could draw at a time.
    private var surfaceHandlers: [UUID: (IOSurface) -> Void] = [:]

    @discardableResult
    func addSurfaceHandler(_ handler: @escaping (IOSurface) -> Void) -> UUID {
        let token = UUID()
        surfaceHandlers[token] = handler
        return token
    }

    func removeSurfaceHandler(_ token: UUID) {
        surfaceHandlers.removeValue(forKey: token)
    }

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.normanaugscheller.anyplay.capture")
    private var frameCounter = 0
    private var changeCounter = 0
    private var lastFingerprint: UInt64 = 0
    /// Set to a path to have the next frame written there as a PNG. Diagnosis only:
    /// without a picture there is no way to check from a script what is being
    /// captured — a frame rate says nothing about the content.
    nonisolated(unsafe) static var dumpNextFrameTo: String?
    private static let dumpContext = CIContext()
    private var settings = CaptureSettings()
    private var rateTimer: Timer?
    private(set) var window: TargetWindow?

    func start(window: TargetWindow, settings: CaptureSettings = Settings.captureSettings) async {
        await stop()
        state = .starting
        self.window = window
        self.settings = settings

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                state = .failed(L10n.tr("error.windowGone"))
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            // Real pixels, or the picture is blurry on a Retina display. The factor
            // comes from the filter, not from a guessed display.
            let scale = CGFloat(filter.pointPixelScale)
            let size = CGSize(width: filter.contentRect.width * scale,
                              height: filter.contentRect.height * scale)
            let configuration = makeConfiguration(pixelSize: size)
            pixelSize = CGSize(width: configuration.width, height: configuration.height)

            let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try await newStream.startCapture()
            stream = newStream
            state = .running
            DiagnosticLog.shared?.line("SOURCE id=\(window.windowID) \(window.appName) "
                                     + "\"\(window.displayTitle)\" frame=\(window.frame) "
                                     + "stream=\(Int(size.width))x\(Int(size.height))px")
            startRateTimer()
        } catch {
            state = .failed(Self.explain(error))
        }
    }

    /// Follows a change in the source's size or display.
    ///
    /// Without this, ScreenCaptureKit keeps the old resolution and scales smaller
    /// content into it with black bars. The pixel factor is taken from the display the
    /// window is on now — after moving to an external monitor it may differ.
    func updateSource(frame: CGRect) async {
        guard let stream, frame.width > 0, frame.height > 0 else { return }
        let scale = ScreenCoordinates.backingScale(forWindowServerRect: frame)
        let newSize = CGSize(width: (frame.width * scale).rounded(),
                             height: (frame.height * scale).rounded())
        guard abs(newSize.width - pixelSize.width) > 1 || abs(newSize.height - pixelSize.height) > 1
        else { return }
        do {
            try await stream.updateConfiguration(makeConfiguration(pixelSize: newSize))
            pixelSize = newSize
        } catch {
            DiagnosticLog.shared?.line("updateConfiguration failed: \(error.localizedDescription)")
        }
    }

    /// Applies changed settings (frame rate, mouse pointer) to the running stream.
    func applySettings() async {
        settings = Settings.captureSettings
        guard let stream, pixelSize != .zero else { return }
        do {
            try await stream.updateConfiguration(makeConfiguration(pixelSize: pixelSize))
            DiagnosticLog.shared?.line("Settings applied: \(settings.maximumFPS) fps, "
                                     + "cursor=\(settings.showsCursor)")
        } catch {
            DiagnosticLog.shared?.line("Settings not applied: \(error.localizedDescription)")
        }
    }

    func stop() async {
        rateTimer?.invalidate()
        rateTimer = nil
        framesPerSecond = 0
        changedFramesPerSecond = 0
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        if case .failed = state {} else { state = .idle }
    }

    private func makeConfiguration(pixelSize size: CGSize) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.maximumFPS))
        configuration.queueDepth = settings.queueDepth
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = settings.showsCursor
        configuration.scalesToFit = true
        return configuration
    }

    private func startRateTimer() {
        frameCounter = 0
        changeCounter = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.framesPerSecond = self.frameCounter
                self.changedFramesPerSecond = self.changeCounter
                self.frameCounter = 0
                self.changeCounter = 0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rateTimer = timer
    }

    nonisolated private static func explain(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == -3801 {
            return L10n.tr("error.screenRecordingDenied")
        }
        return nsError.localizedDescription
    }
}

// MARK: - Frames

extension CaptureSession: SCStreamOutput, SCStreamDelegate {

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let status = Self.status(of: sampleBuffer)
        // ScreenCaptureKit is change-driven: only a complete frame carries a new
        // picture. Everything else means "nothing changed".
        guard status == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else {
            if let status { Task { @MainActor in self.lastFrameStatus = status } }
            return
        }
        if let path = Self.dumpNextFrameTo {
            Self.dumpNextFrameTo = nil
            Self.writePNG(pixelBuffer, to: path)
        }
        let fingerprint = Self.fingerprint(of: pixelBuffer)
        Task { @MainActor in
            self.lastFrameStatus = status
            self.frameCounter += 1
            if fingerprint != self.lastFingerprint {
                self.lastFingerprint = fingerprint
                self.changeCounter += 1
            }
            for handler in self.surfaceHandlers.values { handler(surface) }
        }
    }

    nonisolated private static func writePNG(_ buffer: CVPixelBuffer, to path: String) {
        let image = CIImage(cvPixelBuffer: buffer)
        guard let png = dumpContext.pngRepresentation(
            of: image, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        DiagnosticLog.shared?.line("FRAME written to \(path)")
    }

    /// A cheap signature of one frame: 64 pixels on a fixed grid, mixed together.
    /// Enough to tell a moving picture from a frozen one, and far cheaper than
    /// comparing whole frames sixty times a second.
    nonisolated private static func fingerprint(of buffer: CVPixelBuffer) -> UInt64 {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return 0 }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 8, height > 8 else { return 0 }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 0xcbf29ce484222325
        for row in 0..<8 {
            let y = height * (2 * row + 1) / 16
            for column in 0..<8 {
                let x = width * (2 * column + 1) / 16
                let value = UInt64(bytes[y * bytesPerRow + x * 4])
                hash = (hash ^ value) &* 0x100000001b3
            }
        }
        return hash
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.state = .failed(Self.explain(error))
        }
    }

    nonisolated private static func status(of buffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return nil }
        return SCFrameStatus(rawValue: raw)
    }
}
