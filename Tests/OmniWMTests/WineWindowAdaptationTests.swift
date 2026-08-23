// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/BarutSRB/OmniWM

import ApplicationServices
import Foundation
import Testing
@testable import OmniWM

@Suite("Wine window adaptation")
@MainActor
struct WineWindowAdaptationTests {
    private func makeFacts(
        subrole: String = kAXUnknownSubrole as String,
        hasCloseButton: Bool = false,
        hasFullscreenButton: Bool = false,
        hasZoomButton: Bool = false,
        hasMinimizeButton: Bool = false,
        windowServerLevel: Int32? = 0,
        parentWindowId: UInt32 = 0,
        attributeFetchSucceeded: Bool = true
    ) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: "Beacon Pines",
            ax: AXWindowFacts(
                role: kAXWindowRole as String,
                subrole: subrole,
                title: nil,
                hasCloseButton: hasCloseButton,
                hasFullscreenButton: hasFullscreenButton,
                fullscreenButtonEnabled: nil,
                hasZoomButton: hasZoomButton,
                hasMinimizeButton: hasMinimizeButton,
                appPolicy: .regular,
                bundleId: "org.wine.beacon-pines",
                attributeFetchSucceeded: attributeFetchSucceeded
            ),
            sizeConstraints: nil,
            windowServer: windowServerLevel.map {
                WindowServerInfo(
                    id: 42,
                    pid: 7_001,
                    level: $0,
                    frame: CGRect(x: 0, y: 0, width: 2580, height: 1080),
                    parentId: parentWindowId
                )
            }
        )
    }

    @Test("borderless top-level AXUnknown window is admitted with wine hints")
    func admitsWineStyleWindow() {
        let engine = WindowRuleEngine()
        engine.wineWindowAdaptationEnabled = true
        let decision = engine.decision(for: makeFacts(), token: nil, appFullscreen: false)
        #expect(decision.disposition == .managed)
        #expect(decision.admissionHints.wineStyleAdaptation == true)
        #expect(decision.source == .builtInRule(WindowRuleEngine.wineAdaptationRuleName))
    }

    @Test("AXFullScreen misreport does not suppress wine admission hints")
    func keepsHintsUnderFullscreenMisreport() {
        let engine = WindowRuleEngine()
        engine.wineWindowAdaptationEnabled = true
        let decision = engine.decision(for: makeFacts(), token: nil, appFullscreen: true)
        #expect(decision.disposition == .managed)
        #expect(decision.admissionHints.wineStyleAdaptation == true)
    }

    @Test("adaptation can be disabled")
    func disabledFallsBackToHeuristic() {
        let engine = WindowRuleEngine()
        engine.wineWindowAdaptationEnabled = false
        let decision = engine.decision(for: makeFacts(), token: nil, appFullscreen: false)
        #expect(decision.admissionHints.wineStyleAdaptation == false)
        #expect(decision.disposition != .managed || decision.source != .builtInRule(WindowRuleEngine.wineAdaptationRuleName))
    }

    @Test("standard-subrole borderless windows are not wine-style")
    func rejectsStandardSubrole() {
        #expect(!WindowRuleEngine.isWineStyleWindow(makeFacts(subrole: kAXStandardWindowSubrole as String)))
    }

    @Test("windows with a parent are not wine-style")
    func rejectsChildWindows() {
        #expect(!WindowRuleEngine.isWineStyleWindow(makeFacts(parentWindowId: 7)))
    }

    @Test("elevated-level surfaces are not wine-style")
    func rejectsElevatedLevel() {
        #expect(!WindowRuleEngine.isWineStyleWindow(makeFacts(windowServerLevel: 3)))
    }

    @Test("windows with buttons are not wine-style")
    func rejectsWindowsWithButtons() {
        #expect(!WindowRuleEngine.isWineStyleWindow(makeFacts(hasCloseButton: true)))
        #expect(!WindowRuleEngine.isWineStyleWindow(makeFacts(hasZoomButton: true)))
    }

    @Test("missing WindowServer evidence is not wine-style")
    func rejectsMissingEvidence() {
        #expect(!WindowRuleEngine.isWineStyleWindow(makeFacts(windowServerLevel: nil)))
    }

    @Test("degraded attribute fetch with full wine signature still admits")
    func admitsUnderDegradedAttributeFetch() {
        #expect(WindowRuleEngine.isWineStyleWindow(makeFacts(attributeFetchSucceeded: false)))
        let engine = WindowRuleEngine()
        engine.wineWindowAdaptationEnabled = true
        let decision = engine.decision(
            for: makeFacts(attributeFetchSucceeded: false),
            token: nil,
            appFullscreen: false
        )
        #expect(decision.disposition == .managed)
        #expect(decision.admissionHints.wineStyleAdaptation == true)
    }
}
