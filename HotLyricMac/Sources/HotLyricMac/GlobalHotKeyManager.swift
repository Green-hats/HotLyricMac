import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager: @unchecked Sendable {
    enum Action: UInt32, CaseIterable {
        case playPause = 1
        case previous = 2
        case next = 3
        case toggleLock = 4
        case toggleVisibility = 5
    }

    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []
    private let actions: [UInt32: @MainActor () -> Void]
    private(set) var errors: [String] = []

    init(actions: [Action: @MainActor () -> Void]) {
        self.actions = Dictionary(uniqueKeysWithValues: actions.map { ($0.key.rawValue, $0.value) })
        installHandler()
        register(.playPause, keyCode: UInt32(kVK_Space))
        register(.previous, keyCode: UInt32(kVK_LeftArrow))
        register(.next, keyCode: UInt32(kVK_RightArrow))
        register(.toggleLock, keyCode: UInt32(kVK_ANSI_L))
        register(.toggleVisibility, keyCode: UInt32(kVK_ANSI_H))
    }

    deinit {
        for hotKey in hotKeys { if let hotKey { UnregisterEventHotKey(hotKey) } }
        if let handler { RemoveEventHandler(handler) }
    }

    private func installHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.perform(identifier.id)
                return noErr
            },
            1,
            &type,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status != noErr { errors.append("无法安装快捷键处理器（\(status)）") }
    }

    private func register(_ action: Action, keyCode: UInt32) {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x484C5943, id: action.rawValue) // HLYC
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            hotKeys.append(reference)
        } else {
            errors.append("\(label(action)) 注册失败（\(status)）")
        }
    }

    private func perform(_ identifier: UInt32) {
        guard let action = actions[identifier] else { return }
        Task { @MainActor in action() }
    }

    private func label(_ action: Action) -> String {
        switch action {
        case .playPause: "⌥⌘Space"
        case .previous: "⌥⌘←"
        case .next: "⌥⌘→"
        case .toggleLock: "⌥⌘L"
        case .toggleVisibility: "⌥⌘H"
        }
    }
}
