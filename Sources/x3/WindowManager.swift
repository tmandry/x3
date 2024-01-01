import Carbon
import Carbon.HIToolbox
import os
import Quartz
import Swindler

public var X3_LOGGER: Logger!
var log: Logger { X3_LOGGER }

extension Swindler.State {
    var focusedWindow: Window? {
        get {
            return self.frontmostApplication.value?.mainWindow.value
        }
    }
}

class ContainerNodeWmData: Codable {
    var unstackLayout: Layout?
}

let resizeAmt: Float = 0.05

let STATE = CodingUserInfoKey(rawValue: "state")!

/// Defines the basic window management operations and their behavior.
public final class WindowManager: Encodable, Decodable {
    var state: Swindler.State!
    public var reload: Optional<(WindowManager) -> ()> = nil

    var spaces: [Int: TreeLayout] = [:]
    var curSpaceId: Int
    var curSpace: TreeLayout { spaces[curSpaceId]! }

    // Since we can't see windows from other spaces when first starting, we have
    // to recover spaces lazily, holding onto their recovery data until
    // the user switches to the space again.
    var pendingSpaceData: [Data] = []

    var focus: Crawler? {
        get {
            spaces[curSpaceId]!.focus
        }
        set {
            spaces[curSpaceId]!.focus = newValue
        }
    }

    var addNewWindows: Bool = false

    enum CodingKeys: CodingKey {
        case addNewWindows, spaceData
    }

    public init(state: Swindler.State) {
        self.state = state
        curSpaceId = state.mainScreen!.spaceId
        spaces[curSpaceId] = TreeLayout(Tree(screen: state.mainScreen!))
        setup()
    }

    private init() {
        curSpaceId = 0
    }

    /// Don't use – use recover instead.
    public init(from decoder: Decoder) throws {
        state = (decoder.userInfo[STATE]! as! Swindler.State)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addNewWindows = try container.decode(Bool.self, forKey: .addNewWindows)

        var spaceData = try container.decode([Data].self, forKey: .spaceData)

        curSpaceId = state.mainScreen!.spaceId
        let curSpaceData = spaceData.remove(at: 0) // first space is always the current one.
        log.info("Restoring current space")
        try restoreCurrentSpace(curSpaceId, curSpaceData)

        pendingSpaceData = spaceData

        setup()
    }

    public static func recover(from data: Data, state: Swindler.State) throws -> WindowManager {
        let decoder = JSONDecoder()
        decoder.userInfo[STATE] = state
        return try decoder.decode(WindowManager.self, from: data)
    }

    public func serialize() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }


    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(addNewWindows, forKey: .addNewWindows)
        let treeEncoder = JSONEncoder()

        var spaceTrees: [Data] = []
        func encodeTree(forSpace space: TreeLayout) throws {
            spaceTrees.append(try treeEncoder.encode(space.tree.peek()))
        }
        try encodeTree(forSpace: spaces[curSpaceId]!)
        for (id, space) in spaces {
            if id == curSpaceId {
                // We already encoded the current space as the first value.
                continue
            }
            // TODO: Skip empty trees.
            try encodeTree(forSpace: space)
        }
        spaceTrees.append(contentsOf: pendingSpaceData)

        try container.encode(spaceTrees, forKey: .spaceData)
    }

    private func restoreCurrentSpace(_ id: Int, _ data: Data) throws {
        log.debug("Attempting to restore: \(String(decoding: data, as: UTF8.self))")
        let tr = try Tree.inflate(
            from: JSONDecoder(),
            data: data,
            screen: state.mainScreen!,
            state: state)
        spaces[id] = TreeLayout(tr)
        curSpaceId = id

        // update selection.
        curSpace.onFocusedWindowChanged(window: state.focusedWindow)
        // refresh because the screen layout may have changed.
        curSpace.tree.peek().refresh()

        log.info("Restored space successfully")
    }

    private func initCurrentSpace(id: Int) {
        curSpaceId = id
        if self.spaces.keys.contains(id) {
            return
        }
        log.debug("Initializing space \(id)")
        let screen = state.mainScreen!
        for (idx, data) in pendingSpaceData.enumerated() {
            do {
                try restoreCurrentSpace(id, data)
                pendingSpaceData.remove(at: idx)
                return
            } catch let error {
                log.debug("Failed to restore space: \(String(describing: error))")
            }
        }
        log.info("Initialized new space \(id)")
        spaces[id] = TreeLayout(Tree(screen: screen))
    }

    private func setup() {
        initCurrentSpace(id: curSpaceId)
        state.on { (event: SpaceWillChangeEvent) in
            log.debug("\(String(describing: event))")
            let newSpace = self.state.mainScreen!.spaceId
            if self.spaces.keys.contains(newSpace) {
                // If this is a space we've seen before, eagerly switch to improve responsiveness.
                self.curSpaceId = newSpace
                log.debug("curSpaceId is now \(newSpace)")
            }
            self.ensureTreeScreenIsCurrent()
        }
        state.on { (event: SpaceDidChangeEvent) in
            log.debug("\(String(describing: event))")
            let newSpace = self.state.mainScreen!.spaceId
            self.initCurrentSpace(id: newSpace)
            assert(self.curSpaceId == newSpace)
            log.debug("curSpaceId is now \(newSpace)")
        }

        state.on { (event: WindowCreatedEvent) in
            if self.addNewWindows {
                self.curSpace.addWindow(event.window)
                self.raiseFocus()
            }
        }

        state.on { (event: WindowDestroyedEvent) in
            // FIXME: This is a bug, we should check all spaces for the window.
            self.curSpace.onWindowDestroyed(event.window)
            self.raiseFocus()
        }

        // TODO: Add FocusedWindowChangedEvent to Swindler
        state.on { (event: FrontmostApplicationChangedEvent) in
            self.curSpace.onFocusedWindowChanged(window: event.newValue?.focusedWindow.value)
        }
        state.on { (event: ApplicationFocusedWindowChangedEvent) in
            if event.application == self.state.frontmostApplication.value {
                self.curSpace.onFocusedWindowChanged(window: event.newValue)
            }
        }

        state.on { (event: WindowFrameChangedEvent) in
            // Apparently macOS does special things when you hold down option and resize.
            // Command doesn't have this behavior.
            let cmdPressed = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Command))
            if cmdPressed && event.external {
                self.curSpace.onUserResize(event.window, oldFrame: event.oldValue, newFrame: event.newValue)
            }
        }

        state.on { (event: ScreenLayoutChangedEvent) in
            self.ensureTreeScreenIsCurrent()
        }
    }

    private func ensureTreeScreenIsCurrent() {
        // TODO: Update all spaces on screen when multiple screens are supported.
        if let screen = state.mainScreen {
            curSpace.onScreenChanged(screen)
        }
    }

    public func registerHotKeys(_ hotKeys: HotKeyManager) {
        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey) {
            self.curSpace.moveFocus(.right)
            self.raiseFocus()
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey) {
            self.curSpace.moveFocus(.left)
            self.raiseFocus()
        }
        hotKeys.register(keyCode: kVK_ANSI_J, modifierKeys: optionKey) {
            self.curSpace.moveFocus(.down)
            self.raiseFocus()
        }
        hotKeys.register(keyCode: kVK_ANSI_K, modifierKeys: optionKey) {
            self.curSpace.moveFocus(.up)
            self.raiseFocus()
        }
        hotKeys.register(keyCode: kVK_ANSI_A, modifierKeys: optionKey) {
            self.curSpace.focusParent()
        }
        hotKeys.register(keyCode: kVK_ANSI_D, modifierKeys: optionKey) {
            self.curSpace.focusChild()
        }

        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey | shiftKey) {
            self.curSpace.moveFocusedNode(.right)
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey | shiftKey) {
            self.curSpace.moveFocusedNode(.left)
        }
        hotKeys.register(keyCode: kVK_ANSI_J, modifierKeys: optionKey | shiftKey) {
            self.curSpace.moveFocusedNode(.down)
        }
        hotKeys.register(keyCode: kVK_ANSI_K, modifierKeys: optionKey | shiftKey) {
            self.curSpace.moveFocusedNode(.up)
        }

        hotKeys.register(keyCode: kVK_RightArrow, modifierKeys: optionKey | cmdKey) {
            self.curSpace.resize(to: .right, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_LeftArrow, modifierKeys: optionKey | cmdKey) {
            self.curSpace.resize(to: .left, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_DownArrow, modifierKeys: optionKey | cmdKey) {
            self.curSpace.resize(to: .down, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_UpArrow, modifierKeys: optionKey | cmdKey) {
            self.curSpace.resize(to: .up, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_RightArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.curSpace.resize(to: .right, screenPct: -resizeAmt)
        }
        hotKeys.register(keyCode: kVK_LeftArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.curSpace.resize(to: .left, screenPct: -resizeAmt)
        }
        hotKeys.register(keyCode: kVK_DownArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.curSpace.resize(to: .down, screenPct: -resizeAmt)
        }
        hotKeys.register(keyCode: kVK_UpArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.curSpace.resize(to: .up, screenPct: -resizeAmt)
        }

        hotKeys.register(keyCode: kVK_ANSI_D, modifierKeys: optionKey | shiftKey) {
            log.debug("\(String(describing: self.curSpace))")
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifierKeys: optionKey) {
            self.curSpace.forceRefresh()
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifierKeys: optionKey | shiftKey) {
            self.reload?(self)
        }

        hotKeys.register(keyCode: kVK_ANSI_X, modifierKeys: optionKey) {
            if let window = self.state.focusedWindow {
                self.curSpace.addWindow(window)
            }
        }
        hotKeys.register(keyCode: kVK_ANSI_X, modifierKeys: optionKey | shiftKey) {
            self.curSpace.removeCurrentWindow()
        }

        hotKeys.register(keyCode: kVK_ANSI_Minus, modifierKeys: optionKey) {
            self.curSpace.split(.vertical)
        }
        hotKeys.register(keyCode: kVK_ANSI_Backslash, modifierKeys: optionKey) {
            self.curSpace.split(.horizontal)
        }

        hotKeys.register(keyCode: kVK_ANSI_T, modifierKeys: optionKey) {
            self.curSpace.stack(layout: .tabbed)
        }
        hotKeys.register(keyCode: kVK_ANSI_S, modifierKeys: optionKey) {
            self.curSpace.stack(layout: .stacked)
        }
        hotKeys.register(keyCode: kVK_ANSI_E, modifierKeys: optionKey) {
            self.curSpace.unstack()
        }

        hotKeys.register(keyCode: kVK_Return, modifierKeys: optionKey) {
            self.addNewWindows = !self.addNewWindows
        }
    }

    private func raiseFocus() {
        guard let focus = focus,
              case .window(let windowNode) = focus.node else {
            return
        }
        raise(windowNode.window)
    }

    var pendingFrontmostApplication: Swindler.Application?

    private func raise(_ window: Window) {
        // TODO: Add this method to Swindler and test it.
        //
        // We raise the window within the application, then the application
        // itself, to avoid a race where the application is made frontmost but
        // still has another window as its main window. This would cause that
        // window to come to the front, then the correct window some time later.
        //
        // pendingFrontmostApplication is to handle another potential race
        // condition. If a new window is raised before the app responds to the
        // mainWindow.set, we can invoke frontmostApplication.set _after_
        // completing the later raise. Keeping a reference to the source of
        // truth makes sure we always raise the right application.
        //
        // FIXME: Note that we don't explicitly model the other race between two
        // competing mainWindow changes to the same app. We actually should. the
        // remote app's port/main loop is a serializing point so as long as we
        // get our requests to it off in order, we'll be fine. However, I don't
        // think Swindler guarantees this today (arguably a bug).
        pendingFrontmostApplication = window.application
        window.application.mainWindow.set(window).then { _ in
            return self.state.frontmostApplication.set(self.pendingFrontmostApplication!)
        }.catch { err in
            log.error("Error raising window \(window): \(String(describing: err))")
        }
    }
}
