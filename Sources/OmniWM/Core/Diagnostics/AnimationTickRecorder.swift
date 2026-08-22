// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/BarutSRB/OmniWM

import CoreGraphics
import QuartzCore

enum AnimationTickTrace {
    struct Record: Sendable {
        let mediaTime: CFTimeInterval
        let displayId: CGDirectDisplayID
        let intervalMs: Double
        let expectedMs: Double
        let scrollMs: Double
        let closingMs: Double
        let reconcileMs: Double
        let totalMs: Double
        let dropped: Bool
    }

    static let shared = SessionTraceRecorder<Record>(
        sectionTitle: "Animation Tick Timing",
        capacity: 2048
    ) { record in
        let timing = String(
            format: "interval=%.2fms expected=%.2fms scroll=%.2fms"
                + " closing=%.2fms reconcile=%.2fms total=%.2fms",
            record.intervalMs,
            record.expectedMs,
            record.scrollMs,
            record.closingMs,
            record.reconcileMs,
            record.totalMs
        )
        let mediaTime = String(format: "%.3f", record.mediaTime)
        return "t=\(mediaTime) disp=\(record.displayId) \(timing)\(record.dropped ? " DROPPED" : "")"
    }
}
