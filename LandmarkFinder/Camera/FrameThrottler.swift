import Foundation
import QuartzCore

final class FrameThrottler {
    private let minInterval: TimeInterval
    private var lastTime: TimeInterval = 0

    init(maxFPS: Double) {
        self.minInterval = 1.0 / max(1.0, maxFPS)
    }

    func shouldProcess(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        if now - lastTime >= minInterval {
            lastTime = now
            return true
        }
        return false
    }
}
