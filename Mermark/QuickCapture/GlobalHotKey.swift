import AppKit
import Carbon.HIToolbox

/// 앱이 앞에 없을 때도 동작하는 전역 단축키.
/// Carbon의 RegisterEventHotKey를 쓰면 손쉬운 사용 권한 없이도 등록된다.
final class GlobalHotKey {
    /// 강하게 붙들면 deinit이 실행되지 않아 단축키가 영영 해제되지 않는다
    private struct WeakRef {
        weak var value: GlobalHotKey?
    }

    private static var registry: [UInt32: WeakRef] = [:]
    private static var eventHandler: EventHandlerRef?
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x4D524B31  // 'MRK1'

    private let id: UInt32
    private let onPress: () -> Void
    private var reference: EventHotKeyRef?

    /// 등록에 실패하면(다른 앱이 이미 쓰는 조합 등) nil을 돌려준다.
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress
        self.id = Self.nextID
        Self.nextID += 1

        guard Self.installHandlerIfNeeded() else { return nil }

        Self.registry[id] = WeakRef(value: self)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, reference != nil else {
            Self.registry[id] = nil
            return nil
        }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        Self.registry[id] = nil
    }

    private static func installHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard result == noErr else { return result }
                GlobalHotKey.registry[hotKeyID.id]?.value?.onPress()
                return noErr
            },
            1, &spec, nil, &eventHandler
        )
        return status == noErr
    }
}
