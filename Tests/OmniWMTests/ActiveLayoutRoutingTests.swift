// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/BarutSRB/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ActiveLayoutRoutingTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1600, height: 900)
    private let staleNiriFrame = CGRect(x: 40, y: 60, width: 320, height: 240)

    func testLayoutTopologyProjectsNiriEngine() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let niriEngine = try XCTUnwrap(controller.niriEngine)
        let workspaceId = try makeTransientWorkspace(named: "60", controller: controller)
        let token = addManagedWindow(pid: 950, windowId: 1, to: workspaceId, controller: controller)

        controller.workspaceManager.withEngineMutationScope {
            _ = niriEngine.addWindow(token: token, to: workspaceId, afterSelection: nil)
        }

        let topology = controller.workspaceManager.layoutTopology(for: workspaceId)

        XCTAssertTrue(topology.hasColumns)
        XCTAssertTrue(topology.containsNiriWindow(token))
        XCTAssertFalse(topology.isFullscreen(token))
    }

    func testEntryOrderingFollowsNiriColumns() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let niriEngine = try XCTUnwrap(controller.niriEngine)
        let workspaceId = try makeTransientWorkspace(named: "62", controller: controller)
        let firstToken = addManagedWindow(pid: 952, windowId: 1, to: workspaceId, controller: controller)
        let secondToken = addManagedWindow(pid: 952, windowId: 2, to: workspaceId, controller: controller)

        controller.workspaceManager.withEngineMutationScope {
            _ = niriEngine.addWindow(token: secondToken, to: workspaceId, afterSelection: nil)
            _ = niriEngine.addWindow(token: firstToken, to: workspaceId, afterSelection: nil)
        }

        let seededColumnTokens = niriEngine.columns(in: workspaceId).flatMap { $0.windowNodes.map(\.token) }
        XCTAssertEqual(seededColumnTokens, [secondToken, firstToken])

        let entries = controller.workspaceManager.entries(in: workspaceId)
        let ordered = WorkspaceEntryOrdering.orderedEntries(
            entries,
            topology: controller.workspaceManager.layoutTopology(for: workspaceId)
        )

        XCTAssertEqual(ordered.map(\.token), [secondToken, firstToken])
    }

    func testKeyboardFocusFrameQueriesNiriEngine() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let niriEngine = try XCTUnwrap(controller.niriEngine)
        let workspaceId = try makeTransientWorkspace(named: "64", controller: controller)
        let token = addManagedWindow(pid: 954, windowId: 1, to: workspaceId, controller: controller)
        let niriFrame = staleNiriFrame

        controller.workspaceManager.withEngineMutationScope {
            let node = niriEngine.addWindow(token: token, to: workspaceId, afterSelection: nil)
            node.renderedFrame = niriFrame
        }

        XCTAssertEqual(controller.preferredKeyboardFocusFrame(for: token), niriFrame)
    }

    func testKeyboardFocusFrameIsNilWhenEngineHasNoNode() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let workspaceId = try makeTransientWorkspace(named: "66", controller: controller)
        let token = addManagedWindow(pid: 956, windowId: 1, to: workspaceId, controller: controller)

        XCTAssertNil(controller.preferredKeyboardFocusFrame(for: token))
    }

    func testFocusConfirmationActivatesNiriEngine() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let niriEngine = try XCTUnwrap(controller.niriEngine)
        let workspaceId = try makeTransientWorkspace(named: "68", controller: controller)
        let mainToken = addManagedWindow(pid: 958, windowId: 1, to: workspaceId, controller: controller)

        var niriNode: NiriWindow?
        controller.workspaceManager.withEngineMutationScope {
            niriNode = niriEngine.addWindow(token: mainToken, to: workspaceId, afterSelection: nil)
        }
        let entry = try XCTUnwrap(controller.workspaceManager.entry(for: mainToken))

        controller.axEventHandler.handleManagedAppActivation(
            entry: entry,
            isWorkspaceActive: true,
            appFullscreen: false,
            confirmRequest: false
        )

        XCTAssertEqual(
            controller.workspaceManager.niriViewportState(for: workspaceId).selectedNodeId,
            niriNode?.id
        )
    }

    func testTabRailsProjectForActiveNiriWorkspace() throws {
        let controller = makeController()
        controller.niriLayoutHandler.enableNiriLayout()
        let niriEngine = try XCTUnwrap(controller.niriEngine)
        let monitor = Monitor(
            id: .init(displayId: 20_001), displayId: 20_001,
            frame: screenFrame, visibleFrame: screenFrame,
            hasNotch: false, name: "Rails"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        let niriWorkspaceId = try makeTransientWorkspace(named: "70", controller: controller)

        let pid = pid_t(960)
        let token = addManagedWindow(pid: pid, windowId: 1, to: niriWorkspaceId, controller: controller)
        let secondToken = addManagedWindow(pid: pid, windowId: 2, to: niriWorkspaceId, controller: controller)
        controller.workspaceManager.withEngineMutationScope {
            let firstNode = niriEngine.addWindow(token: token, to: niriWorkspaceId, afterSelection: nil)
            let secondNode = niriEngine.addWindow(
                token: secondToken,
                to: niriWorkspaceId,
                afterSelection: firstNode.id
            )
            if let column = niriEngine.columns(in: niriWorkspaceId).first {
                var state = ViewportState(selectedNodeId: firstNode.id)
                _ = niriEngine.consumeWindow(
                    secondNode,
                    into: column,
                    enteringFrom: .right,
                    in: niriWorkspaceId,
                    motion: .disabled,
                    state: &state,
                    workingFrame: screenFrame,
                    gaps: 10,
                    orientation: .horizontal
                )
                column.displayMode = .tabbed
                column.renderedFrame = staleNiriFrame
            }
        }
        let column = try XCTUnwrap(niriEngine.columns(in: niriWorkspaceId).first)
        XCTAssertTrue(column.isTabbed)

        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(niriWorkspaceId, on: monitor.id))
        XCTAssertEqual(controller.niriLayoutHandler.desiredTabRailInfos().map(\.workspaceId), [niriWorkspaceId])
    }

    private func makeTransientWorkspace(
        named name: String,
        controller: WMController
    ) throws -> WorkspaceDescriptor.ID {
        controller.settings.workspaceConfigurations.append(WorkspaceConfiguration(name: name))
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

    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMActiveLayoutRoutingTests-\(UUID().uuidString)", isDirectory: true)
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
