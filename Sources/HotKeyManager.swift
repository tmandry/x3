import AppKit
import Carbon

private let hotKeySignature = fourCharCodeFrom("X3WM")

class HotKeyManager {
    private var handlers: [() -> ()] = []

    func register(keyCode: Int, modifierKeys: Int, handler: @escaping () -> ()) {
        handlers.append(handler)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = hotKeySignature
        hotKeyID.id = UInt32(handlers.count - 1)

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind  = OSType(kEventHotKeyPressed)

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(),
            {(nextHandler, event, userData) -> OSStatus in
                return HotKeyManager.handleCarbonEvent(event, userData)
            }, 1, &eventType, selfPtr, nil)

        var hotKeyRef: EventHotKeyRef?
        let _ = RegisterEventHotKey(UInt32(keyCode), UInt32(modifierKeys), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    static func handleCarbonEvent(_ event: EventRef?, _ userData: UnsafeMutableRawPointer?)
    -> OSStatus {
        guard let event = event else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(event, UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        if err != noErr {
            return err
        }

        guard hotKeyID.signature == hotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        let self_ = Unmanaged<HotKeyManager>.fromOpaque(userData!).takeUnretainedValue()
        return self_.handleHotKey(eventKind: GetEventKind(event), hotKeyID: hotKeyID)
    }

    private func handleHotKey(eventKind: UInt32, hotKeyID: EventHotKeyID) -> OSStatus {
        debugPrint("!!!Got event: \(eventKind) \(hotKeyID)")
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            handlers[Int(hotKeyID.id)]()
            return noErr
        case UInt32(kEventHotKeyReleased):
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }
}

private func fourCharCodeFrom(_ string : String) -> FourCharCode {
    assert(string.characters.count == 4, "String length must be 4")
    var result : FourCharCode = 0
    for char in string.utf16 {
        result = (result << 8) + FourCharCode(char)
    }
    return result
}
