import AppKit

enum MenuIconState: String, CaseIterable {
    case running = "MenuRunning"
    case stopped = "MenuStopped"
    case processing = "MenuProcessing"
    case error = "MenuError"

    init(_ state: SwitcherState) {
        if state.isBusy || state.isWaitingForQuit { self = .processing }
        else if state.error != nil { self = .error }
        else { self = state.isRunning ? .running : .stopped }
    }

    var description: String {
        switch self {
        case .running: "运行中"
        case .stopped: "未运行"
        case .processing: "处理中"
        case .error: "异常"
        }
    }
}

@MainActor
final class MenuBarIcons {
    static let size = NSSize(width: 20, height: 20)
    private let images: [MenuIconState: NSImage]
    private let processingFrame: NSImage?
    private let processingSpinner: NSImage?

    init() {
        // Older SwiftPM accessors only probe the app root and the original build path.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("CodeXwitch_CodeXwitchKit.bundle")
        let bundle = packaged.flatMap(Bundle.init(url:)) ?? Bundle.module
        func load(_ name: String) -> NSImage? {
            guard let url = bundle.url(forResource: name, withExtension: "pdf", subdirectory: "Icons"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.size = Self.size
            image.isTemplate = true
            return image
        }
        images = Dictionary(uniqueKeysWithValues: MenuIconState.allCases.compactMap { state in
            load(state.rawValue).map { (state, $0) }
        })
        processingFrame = load("ProcessingFrame")
        processingSpinner = load("ProcessingSpinner")
    }

    func image(for state: MenuIconState, rotation: CGFloat = 0) -> NSImage? {
        guard state == .processing, let frame = processingFrame, let spinner = processingSpinner else {
            return images[state]
        }
        let image = NSImage(size: Self.size, flipped: false) { rect in
            frame.draw(in: rect)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: -rotation)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            spinner.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
