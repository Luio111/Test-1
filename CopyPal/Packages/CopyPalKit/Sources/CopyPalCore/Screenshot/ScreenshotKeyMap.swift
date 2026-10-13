/// Keys the screenshot overlay reacts to (M11).
public enum ScreenshotKey: Sendable, Equatable {
    case escape
    /// ↩ or keypad Enter.
    case confirm
    case space
    case tab
    case up
    case down
    case left
    case right
}

/// Physical keys, matched by key code like `PopupKeyMap`, so layouts do not matter.
public enum ScreenshotKeyMap {
    public static func key(forKeyCode keyCode: UInt16) -> ScreenshotKey? {
        switch keyCode {
        case PopupKeyMap.escape: .escape
        case PopupKeyMap.returnKey, PopupKeyMap.keypadEnter: .confirm
        case 49: .space
        case PopupKeyMap.tab: .tab
        case PopupKeyMap.upArrow: .up
        case PopupKeyMap.downArrow: .down
        case PopupKeyMap.leftArrow: .left
        case PopupKeyMap.rightArrow: .right
        default: nil
        }
    }
}
