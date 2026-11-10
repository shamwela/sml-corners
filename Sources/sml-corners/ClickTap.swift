import CoreGraphics
import Foundation

/// Intercepts left clicks. A press with one finger inside a bound corner is
/// swallowed and its action runs on release; everything else passes through.
final class ClickTap {
    var bindings: [Corner: Binding] = [:]
    private var port: CFMachPort?
    private var pending: Binding?

    func start() -> Bool {
        if port != nil { return true }
        let mask: CGEventMask =
            1 << CGEventType.leftMouseDown.rawValue
            | 1 << CGEventType.leftMouseUp.rawValue
            | 1 << CGEventType.leftMouseDragged.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let tap = Unmanaged<ClickTap>.fromOpaque(refcon!).takeUnretainedValue()
            return tap.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.port = port
        CFRunLoopAddSource(
            CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Returns true if the event should be swallowed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            pending = nil
            return false
        case .leftMouseDown:
            pending = match()
            return pending != nil
        case .leftMouseDragged:
            return pending != nil
        case .leftMouseUp:
            guard let binding = pending else { return false }
            pending = nil
            Actions.run(binding.action)
            return true
        default:
            return false
        }
    }

    private func match() -> Binding? {
        guard let touch = TouchMonitor.shared.singleTouch() else { return nil }
        for (corner, binding) in bindings {
            let z = binding.zone
            let inX: Bool, inY: Bool
            switch corner {
            case .topLeft: (inX, inY) = (touch.x <= z, touch.y >= 1 - z)
            case .topRight: (inX, inY) = (touch.x >= 1 - z, touch.y >= 1 - z)
            case .bottomLeft: (inX, inY) = (touch.x <= z, touch.y <= z)
            case .bottomRight: (inX, inY) = (touch.x >= 1 - z, touch.y <= z)
            }
            if inX && inY { return binding }
        }
        return nil
    }
}
