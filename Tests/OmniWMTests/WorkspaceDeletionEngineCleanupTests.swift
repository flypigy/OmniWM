// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/BarutSRB/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceDeletionEngineCleanupTests: XCTestCase {
    func testDeletingEmptiedWorkspaceRemovesNiriEngineState() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let engine = try XCTUnwrap(controller.niriEngine)
        let workspaceId = try makeTransientWorkspace(named: "97", controller: controller)
        let token = WindowToken(pid: 900, windowId: 1)
        let frame = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let monitor = Monitor(
            id: Monitor.ID(displayId: 900),
            displayId: 900,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Cleanup"
        )
        controller.workspaceManager.withEngineMutationScope {
            _ = engine.addWindow(token: token, to: workspaceId, afterSelection: nil)
            engine.syncWorkspaceAssignments([(workspaceId: workspaceId, monitor: monitor)])
        }
        let niriMonitor = try XCTUnwrap(engine.monitor(for: monitor.id))
        XCTAssertNotNil(engine.root(for: workspaceId))
        XCTAssertTrue(niriMonitor.containsWorkspace(workspaceId))

        removeTransientWorkspace(named: "97", controller: controller)

        XCTAssertNil(controller.workspaceManager.workspaceId(named: "97"))
        XCTAssertNil(engine.root(for: workspaceId))
        XCTAssertNil(engine.findNode(for: token, in: workspaceId))
        XCTAssertFalse(niriMonitor.containsWorkspace(workspaceId))
    }

    func testNiriFullscreenQueryIsScopedToWorkspaceTree() {
        let engine = NiriLayoutEngine()
        let workspaceA = WorkspaceDescriptor.ID()
        let workspaceB = WorkspaceDescriptor.ID()
        let token = WindowToken(pid: 906, windowId: 1)
        let tokenB = WindowToken(pid: 906, windowId: 2)
        let node = engine.addWindow(token: token, to: workspaceA, afterSelection: nil)
        _ = engine.addWindow(token: tokenB, to: workspaceB, afterSelection: nil)
        node.sizingMode = .fullscreen

        XCTAssertTrue(engine.isWindowFullscreen(token, in: workspaceA))
        XCTAssertFalse(engine.isWindowFullscreen(token, in: workspaceB))
    }

    func testWorldViewFullscreenQueryIgnoresStaleNiriState() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let niriEngine = try XCTUnwrap(controller.niriEngine)
        let niriWorkspaceId = try makeTransientWorkspace(named: "95", layoutType: .niri, controller: controller)
        let otherWorkspaceId = try makeTransientWorkspace(named: "96", controller: controller)
        let niriToken = addManagedWindow(pid: 911, windowId: 1, to: niriWorkspaceId, controller: controller)
        let quietToken = addManagedWindow(pid: 917, windowId: 3, to: otherWorkspaceId, controller: controller)

        controller.workspaceManager.withEngineMutationScope {
            _ = niriEngine.addWindow(token: niriToken, to: niriWorkspaceId, afterSelection: nil)
        }

        let world = WorldView(controller: controller)
        XCTAssertFalse(niriEngine.isWindowFullscreen(niriToken, in: niriWorkspaceId))
        XCTAssertFalse(world.isWindowFullscreenInLayout(niriToken))
        XCTAssertNil(niriEngine.findNode(for: quietToken, in: otherWorkspaceId))
        XCTAssertFalse(world.isWindowFullscreenInLayout(quietToken))
    }
    private func makeTransientWorkspace(
        named name: String,
        layoutType: LayoutType = .defaultLayout,
        controller: WMController
    ) throws -> WorkspaceDescriptor.ID {
        controller.settings.workspaceConfigurations.append(WorkspaceConfiguration(name: name, layoutType: layoutType))
        controller.workspaceManager.applySettings()
        return try XCTUnwrap(controller.workspaceManager.workspaceId(named: name))
    }

    private func addManagedWindow(
        pid: pid_t,
        windowId: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        controller: WMController
    ) -> WindowToken {
        controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
    }

    private func removeTransientWorkspace(named name: String, controller: WMController) {
        controller.settings.workspaceConfigurations.removeAll { $0.name == name }
        controller.workspaceManager.applySettings()
    }

    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMWorkspaceDeletionTests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        return WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
    }
}
