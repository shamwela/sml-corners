import Foundation

/// Tracks raw finger positions on every multitouch device via the private
/// MultitouchSupport framework (loaded at runtime, so nothing links against it).
final class TouchMonitor {
    static let shared = TouchMonitor()

    private typealias FrameCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeRawPointer, FrameCallback) -> Void
    private typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Int32
    private typealias Stop = @convention(c) (UnsafeRawPointer) -> Int32

    // MTTouch layout: 96 bytes; state at 20, normalized x/y (0...1, origin bottom-left) at 32/36.
    private static let touchSize = 96
    private static let stateOffset = 20
    private static let xOffset = 32
    private static let yOffset = 36

    private struct Frame {
        var count = 0
        var x: Float = 0
        var y: Float = 0
    }

    private let lock = NSLock()
    private var frames: [UnsafeMutableRawPointer: Frame] = [:]
    private var devices: [UnsafeRawPointer] = []
    private var retained: [CFArray] = []  // keeps device refs alive; never released

    private let createList: CreateList?
    private let register: Register?
    private let unregister: Register?
    private let startDevice: Start?
    private let stopDevice: Stop?

    private init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        func symbol<T>(_ name: String) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        createList = symbol("MTDeviceCreateList")
        register = symbol("MTRegisterContactFrameCallback")
        unregister = symbol("MTUnregisterContactFrameCallback")
        startDevice = symbol("MTDeviceStart")
        stopDevice = symbol("MTDeviceStop")
    }

    private static let callback: FrameCallback = { device, touches, count, _, _ in
        guard let device else { return 0 }
        var frame = Frame()
        if let touches {
            for i in 0..<Int(count) {
                let touch = touches + i * touchSize
                let state = touch.load(fromByteOffset: stateOffset, as: Int32.self)
                // 4 = making contact, 5 = touching. Other states are hover/lift.
                guard state == 4 || state == 5 else { continue }
                if frame.count == 0 {
                    frame.x = touch.load(fromByteOffset: xOffset, as: Float.self)
                    frame.y = touch.load(fromByteOffset: yOffset, as: Float.self)
                }
                frame.count += 1
            }
        }
        let monitor = TouchMonitor.shared
        monitor.lock.lock()
        monitor.frames[device] = frame
        monitor.lock.unlock()
        return 0
    }

    /// (Re)attaches to all current devices. Returns the number found, or nil if the framework is unusable.
    @discardableResult
    func start() -> Int? {
        guard let createList, let register, let startDevice else { return nil }
        for device in devices {
            unregister?(device, Self.callback)
            _ = stopDevice?(device)
        }
        lock.lock()
        frames.removeAll()
        lock.unlock()

        guard let list = createList()?.takeRetainedValue() else { return nil }
        retained.append(list)
        devices = (0..<CFArrayGetCount(list)).compactMap { CFArrayGetValueAtIndex(list, $0) }
        for device in devices {
            register(device, Self.callback)
            _ = startDevice(device, 0)
        }
        return devices.count
    }

    /// Position of the finger if exactly one is touching across all devices.
    func singleTouch() -> (x: Double, y: Double)? {
        lock.lock()
        defer { lock.unlock() }
        let active = frames.values.filter { $0.count > 0 }
        guard active.count == 1, let frame = active.first, frame.count == 1 else { return nil }
        return (Double(frame.x), Double(frame.y))
    }
}
