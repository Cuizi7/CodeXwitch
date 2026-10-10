import AppKit
import XCTest
@testable import CodeXwitchKit

@MainActor
final class MenuBarIconsTests: XCTestCase {
    func testStatePriorityIncludesWaitingAndErrors() {
        var state = SwitcherState()
        XCTAssertEqual(MenuIconState(state), .stopped)
        state.isRunning = true
        XCTAssertEqual(MenuIconState(state), .running)
        state.error = "读取失败"
        XCTAssertEqual(MenuIconState(state), .error)
        state.isBusy = true
        XCTAssertEqual(MenuIconState(state), .processing)
        state.isBusy = false
        state.isWaitingForQuit = true
        XCTAssertEqual(MenuIconState(state), .processing)
    }

    func testEveryStateLoadsAsVisibleTemplateAtMenuSize() throws {
        _ = NSApplication.shared
        let icons = MenuBarIcons()
        for state in MenuIconState.allCases {
            let image = try XCTUnwrap(icons.image(for: state))
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 20, height: 20))
            let bitmap = try render(image)
            XCTAssertTrue((0..<80).contains { y in
                (0..<80).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
            }, "The \(state) asset should actually draw")
            if let directory = ProcessInfo.processInfo.environment["CODEXWITCH_ICON_RENDER_DIR"] {
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(state.rawValue).png"))
            }
        }
    }

    func testProcessingRotatesOnlyTheInnerGlyph() throws {
        _ = NSApplication.shared
        let icons = MenuBarIcons()
        let first = try render(XCTUnwrap(icons.image(for: .processing, rotation: 0)))
        let second = try render(XCTUnwrap(icons.image(for: .processing, rotation: 30)))
        var innerChanges = 0, outerChanges = 0
        for y in 0..<80 {
            for x in 0..<80 {
                let a = first.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let b = second.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if abs(a - b) > 1.0 / 255 {
                    let radius = hypot(CGFloat(x) - 39.5, CGFloat(y) - 39.5)
                    // PDF rasterization extends the spinner to 21 px; the frame starts at 26 px.
                    if radius > 22 { outerChanges += 1 }
                    else if radius <= 19 { innerChanges += 1 }
                }
            }
        }
        XCTAssertGreaterThan(innerChanges, 0, "Processing should visibly rotate")
        XCTAssertEqual(outerChanges, 0, "The hexagonal frame must stay fixed")
    }

    private func render(_ image: NSImage) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 80, height: 80))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
