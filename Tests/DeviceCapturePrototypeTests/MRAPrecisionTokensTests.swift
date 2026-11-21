import AppKit
import SwiftUI
import XCTest
@testable import DeviceCapturePrototype

/// UI-1 视觉 Token 与三域隔离的离线守卫。
final class MRAPrecisionTokensTests: XCTestCase {

    // MARK: - Token 基线

    func testDarkBaselineMatchesProposedV2Values() {
        let t = MRAVisualTokens.dark
        assertRGB(t.canvasPrimary, 0x0F1115, "canvasPrimary")
        assertRGB(t.sidebarBackground, 0x15181E, "sidebarBackground")
        assertRGB(t.surfaceSubtle, 0x1A1E26, "surfaceSubtle")
        assertRGB(t.textPrimary, 0xF1F3F5, "textPrimary")
        assertRGB(t.textSecondary, 0xA0A7B2, "textSecondary")
        assertRGB(t.accentPrimary, 0x0A84FF, "accentPrimary")
        assertRGB(t.stateDFU, 0xF5A623, "stateDFU")
        assertRGB(t.telemetryCyan, 0x22D3EE, "telemetryCyan")
        assertRGB(t.stateSuccess, 0x30D158, "stateSuccess")
        assertRGB(t.stateError, 0xFF453A, "stateError")
        let (_, _, _, alpha) = components(t.hairline)
        XCTAssertEqual(alpha, 0.10, accuracy: 0.02, "hairline must be ~10%")
    }

    func testLightMappingIsSemanticallyDistinctAndDeepTextOnLightCanvas() {
        let dark = MRAVisualTokens.dark
        let light = MRAVisualTokens.light
        XCTAssertNotEqual(
            components(light.canvasPrimary).0,
            components(dark.canvasPrimary).0,
            "light canvas must not reuse the dark canvas"
        )
        // 浅色底应显著更亮。
        XCTAssertGreaterThan(
            relativeLuminance(light.canvasPrimary),
            0.80,
            "light canvas must be a high-readability light background"
        )
        // 深色字在浅色底上必须足够深。
        XCTAssertLessThan(
            relativeLuminance(light.textPrimary),
            0.06,
            "light-mode primary text must be dark charcoal"
        )
        XCTAssertEqual(components(light.hairline).3, 0.10, accuracy: 0.02)
    }

    func testBothModesMeetTextContrastOnCanvasAndSidebar() {
        for tokens in [MRAVisualTokens.dark, MRAVisualTokens.light] {
            XCTAssertGreaterThanOrEqual(
                contrast(tokens.textPrimary, tokens.canvasPrimary),
                7.0,
                "primary text on canvas should reach AAA"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(tokens.textSecondary, tokens.canvasPrimary),
                4.5,
                "secondary text on canvas should reach AA"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(tokens.textPrimary, tokens.sidebarBackground),
                7.0,
                "primary text on sidebar should reach AAA"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(tokens.textSecondary, tokens.sidebarBackground),
                4.5,
                "secondary text on sidebar should reach AA"
            )
        }
    }

    func testSidebarWidthStaysInsideOwnerRange() {
        for tokens in [MRAVisualTokens.dark, MRAVisualTokens.light] {
            XCTAssertTrue(
                (280.0...310.0).contains(Double(tokens.sidebarWidthCompact)),
                "compact rail width \(tokens.sidebarWidthCompact) outside 280–310"
            )
            XCTAssertTrue(
                (280.0...310.0).contains(Double(tokens.sidebarWidthRegular)),
                "regular rail width \(tokens.sidebarWidthRegular) outside 280–310"
            )
        }
        XCTAssertEqual(MRAVisualTokens.dark.sidebarWidthCompact, 288)
        XCTAssertEqual(MRAVisualTokens.dark.sidebarWidthRegular, 294)
    }

    func testTypographyStaysInsideOwnerBands() {
        XCTAssertTrue((13.0...14.0).contains(Double(MRAFont.bodySize)))
        XCTAssertTrue((14.0...16.0).contains(Double(MRAFont.titleSize)))
        XCTAssertTrue((11.0...13.0).contains(Double(MRAFont.monoSize)))
        XCTAssertTrue((11.0...13.0).contains(Double(MRAFont.monoSmallSize)))
        XCTAssertGreaterThanOrEqual(MRAFont.labelSize, 11)
    }

    func testPrecisionResolvesToTokenBaselineAndOtherStylesKeepTheirPalette() {
        let precisionPalette = WorkbenchVisualStyle.precision
            .palette(for: .dark)
        let resolvedPrecision = MRAVisualTokens.resolve(
            style: .precision,
            scheme: .dark,
            palette: precisionPalette)
        assertRGB(resolvedPrecision.canvasPrimary, 0x0F1115, "precision canvas")

        let liquidPalette = WorkbenchVisualStyle.liquid.palette(for: .dark)
        let resolvedLiquid = MRAVisualTokens.resolve(
            style: .liquid,
            scheme: .dark,
            palette: liquidPalette)
        assertSameColor(
            resolvedLiquid.canvasPrimary,
            liquidPalette.windowBackground,
            "liquid canvas")
        assertSameColor(
            resolvedLiquid.accentPrimary,
            liquidPalette.accent,
            "liquid accent")
    }

    func testDerivedPaletteUsesTokenColors() {
        let fallback = WorkbenchVisualStyle.precision.palette(for: .dark)
        let derived = MRAVisualTokens.dark
            .derivedWorkbenchPalette(fallback: fallback)
        assertSameColor(
            derived.accent,
            MRAVisualTokens.dark.accentPrimary,
            "derived accent")
        assertSameColor(
            derived.windowBackground,
            MRAVisualTokens.dark.canvasPrimary,
            "derived canvas")
        assertSameColor(
            derived.success,
            MRAVisualTokens.dark.stateSuccess,
            "derived success")
    }

    // MARK: - 三域隔离 / 结构守卫

    func testStatusPillActionOnlyMovesTheViewedPort() throws {
        let content = try source("MinimalWorkbenchView.swift")
        let start = try XCTUnwrap(
            content.range(of: "private func viewPortFromStatusPill("))
        let body = content[start.lowerBound...].prefix(420)
        XCTAssertTrue(body.contains("observation.setFixedObservationPort(port.id)"))
        XCTAssertTrue(body.contains("navigation.viewPort(port.id)"))
        XCTAssertTrue(body.contains("autoNavigationPaused = true"))
        XCTAssertTrue(body.contains("contextCue = nil"))
        XCTAssertFalse(body.contains("device.selectPort("))
        XCTAssertFalse(body.contains("restore."))
        XCTAssertFalse(body.contains("selectedLiveKey"))
        XCTAssertFalse(body.contains("perform"))
    }

    func testStatusPillsFollowRealPortsInsteadOfAHardcodedCount() throws {
        let content = try source("MinimalWorkbenchView.swift")
        XCTAssertTrue(content.contains("ForEach(device.orderedDisplayPorts)"))
        XCTAssertTrue(content.contains("workbench-port-pill-\\(port.id)"))
        // 恢复模式药丸必须使用既有四语键，不能直接输出英文 "Recovery"。
        XCTAssertTrue(content.contains("stateText: L10n.t(\"恢复模式\")"))
        XCTAssertFalse(content.contains("stateText: L10n.t(\"Recovery\")"))
        XCTAssertFalse(content.contains("ForEach(0..<4)"))
        XCTAssertFalse(content.contains("ForEach(0..<3)"))
    }

    func testLeftRailStillUsesThePhysicalSelectorAndControlGates() throws {
        let content = try source("MinimalWorkbenchView.swift")
        XCTAssertTrue(content.contains("device.selectPort(port)"))
        XCTAssertTrue(content.contains("navigation.clearTaskView()"))
        XCTAssertTrue(content.contains("observation.followLeftControl()"))
        XCTAssertTrue(content.contains("action: { onSelectPort(port) }"))
        XCTAssertTrue(content.contains("enabled: device.canChangePortSelection"))
        XCTAssertTrue(content.contains("workbench-port-\\(port.id)"))
        XCTAssertTrue(content.contains("workbench-enter-dfu"))
        XCTAssertTrue(content.contains("workbench-reboot"))
        XCTAssertTrue(content.contains("workbench-enter-recovery"))
        // 恢复模式的既有门禁只能保留，不能放宽。
        XCTAssertTrue(
            content.contains("&& !device.bootOptionsTestActive"),
            "Recovery must keep the boot-options gate")
    }

    func testTelemetryOnlyShowsExistingFieldsAndNeverInventsValues() throws {
        let content = try source("MinimalWorkbenchView.swift")
        XCTAssertTrue(content.contains("\"PortNumber\""))
        XCTAssertTrue(content.contains("\"RID\""))
        XCTAssertTrue(content.contains("\"ECID\""))
        XCTAssertTrue(content.contains("L10n.t(\"未获取\")"))
        XCTAssertFalse(
            content.contains("BoardID"),
            "UI-1 must not invent a BoardID telemetry field")
        XCTAssertFalse(
            content.contains("ChipID"),
            "UI-1 must not invent a ChipID telemetry field")
    }

    func testSecondColourSourceAndRestoreFilesAreNotEdited() throws {
        let content = try source("MinimalWorkbenchView.swift")
        XCTAssertFalse(
            content.contains("palette.accent"),
            "UI-1 surfaces must not mix the legacy palette accent with tokens")
        XCTAssertTrue(content.contains("MRAVisualTokens.resolve("))
    }

    // MARK: - 工具

    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/\(name)"),
            encoding: .utf8)
    }

    private func components(
        _ color: Color
    ) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("cannot convert SwiftUI Color to sRGB")
            return (0, 0, 0, 0)
        }
        return (
            ns.redComponent,
            ns.greenComponent,
            ns.blueComponent,
            ns.alphaComponent
        )
    }

    private func assertRGB(
        _ color: Color,
        _ hex: UInt32,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (r, g, b, _) = components(color)
        let expectedR = CGFloat((hex >> 16) & 0xFF) / 255
        let expectedG = CGFloat((hex >> 8) & 0xFF) / 255
        let expectedB = CGFloat(hex & 0xFF) / 255
        XCTAssertEqual(r, expectedR, accuracy: 1.5 / 255, "\(label) R", file: file, line: line)
        XCTAssertEqual(g, expectedG, accuracy: 1.5 / 255, "\(label) G", file: file, line: line)
        XCTAssertEqual(b, expectedB, accuracy: 1.5 / 255, "\(label) B", file: file, line: line)
    }

    private func assertSameColor(
        _ lhs: Color,
        _ rhs: Color,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (r1, g1, b1, _) = components(lhs)
        let (r2, g2, b2, _) = components(rhs)
        XCTAssertEqual(r1, r2, accuracy: 1.5 / 255, "\(label) R", file: file, line: line)
        XCTAssertEqual(g1, g2, accuracy: 1.5 / 255, "\(label) G", file: file, line: line)
        XCTAssertEqual(b1, b2, accuracy: 1.5 / 255, "\(label) B", file: file, line: line)
    }

    private func relativeLuminance(_ color: Color) -> CGFloat {
        let (r, g, b, _) = components(color)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r)
            + 0.7152 * channel(g)
            + 0.0722 * channel(b)
    }

    private func contrast(_ lhs: Color, _ rhs: Color) -> CGFloat {
        let a = relativeLuminance(lhs)
        let b = relativeLuminance(rhs)
        let high = max(a, b)
        let low = min(a, b)
        return (high + 0.05) / (low + 0.05)
    }
}
