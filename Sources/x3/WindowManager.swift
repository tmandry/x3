import Carbon
import os
import Swindler

public var X3_LOGGER: Logger!
var log: Logger { X3_LOGGER }

struct TreeWrapper {
    private var tree: Tree

    init(_ tree: Tree) {
        self.tree = tree
    }
}
extension TreeWrapper {
    /// Use this when modifying the tree. It always ensures refresh is called.
    func with(_ f: (Tree) -> Void) -> Void {
        f(self.tree)
        self.tree.refresh()
    }

    /// Use this when only inspecting the tree. You must not modify the tree using the return value
    /// of this function!
    func peek() -> Tree {
        return self.tree
    }
}

extension Swindler.State {
    var focusedWindow: Window? {
        get {
            return self.frontmostApplication.value?.mainWindow.value
        }
    }
}

extension NodeKind {
    func toCrawler() -> Crawler {
        return Crawler(at: self)
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

    var tree: TreeWrapper!
    var focus: Crawler?

    var addNewWindows: Bool = false

    public var focusedWindow: Window? {
        guard let node = focus?.node else { return nil }
        guard case .window(let windowNode) = node else { return nil }
        return windowNode.window
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(addNewWindows, forKey: .addNewWindows)
        let treeEncoder = JSONEncoder()
        let treeData = try treeEncoder.encode(tree.peek())
        try container.encode(treeData, forKey: .tree)
    }

    private init() {}

    /// Don't use – use recover instead.
    public convenience init(from decoder: Decoder) throws {
        self.init()
        state = (decoder.userInfo[STATE]! as! Swindler.State)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addNewWindows = try container.decode(Bool.self, forKey: .addNewWindows)
        let treeData = try container.decode(Data.self, forKey: .tree)
        log.debug("recovery data: \(String(decoding: treeData, as: UTF8.self))")
        let treeDecoder = JSONDecoder()
        tree = TreeWrapper(try Tree.inflate(
            from: treeDecoder, data: treeData, screen: state.screens.last!, state: state))
        setup()
        // Restore the focus state.
        onFocusedWindowChanged(window: state.focusedWindow)
    }

    enum CodingKeys: CodingKey {
        case addNewWindows, tree
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

    public init(state: Swindler.State) {
        self.state = state
        self.tree = TreeWrapper(Tree(screen: state.screens.last!))
        setup()
    }

    private func setup() {
        state.on { (event: WindowCreatedEvent) in
            if self.addNewWindows {
                self.addWindow(event.window)
            }
        }

        state.on { (event: WindowDestroyedEvent) in
            self.onWindowDestroyed(event.window)
        }

        // TODO: Add FocusedWindowChangedEvent to Swindler
        state.on { (event: FrontmostApplicationChangedEvent) in
            self.onFocusedWindowChanged(window: event.newValue?.focusedWindow.value)
        }
        state.on { (event: ApplicationFocusedWindowChangedEvent) in
            if event.application == self.state.frontmostApplication.value {
                self.onFocusedWindowChanged(window: event.newValue)
            }
        }
    }

    public func registerHotKeys(_ hotKeys: HotKeyManager) {
        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey) {
            self.moveFocus(.right)
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey) {
            self.moveFocus(.left)
        }
        hotKeys.register(keyCode: kVK_ANSI_J, modifierKeys: optionKey) {
            self.moveFocus(.down)
        }
        hotKeys.register(keyCode: kVK_ANSI_K, modifierKeys: optionKey) {
            self.moveFocus(.up)
        }
        hotKeys.register(keyCode: kVK_ANSI_A, modifierKeys: optionKey) {
            self.focusParent()
        }
        hotKeys.register(keyCode: kVK_ANSI_D, modifierKeys: optionKey) {
            self.focusChild()
        }

        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.right)
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.left)
        }
        hotKeys.register(keyCode: kVK_ANSI_J, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.down)
        }
        hotKeys.register(keyCode: kVK_ANSI_K, modifierKeys: optionKey | shiftKey) {
            self.moveFocusedNode(.up)
        }

        hotKeys.register(keyCode: kVK_RightArrow, modifierKeys: optionKey | cmdKey) {
            self.resize(to: .right, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_LeftArrow, modifierKeys: optionKey | cmdKey) {
            self.resize(to: .left, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_DownArrow, modifierKeys: optionKey | cmdKey) {
            self.resize(to: .down, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_UpArrow, modifierKeys: optionKey | cmdKey) {
            self.resize(to: .up, screenPct: resizeAmt)
        }
        hotKeys.register(keyCode: kVK_RightArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.resize(to: .right, screenPct: -resizeAmt)
        }
        hotKeys.register(keyCode: kVK_LeftArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.resize(to: .left, screenPct: -resizeAmt)
        }
        hotKeys.register(keyCode: kVK_DownArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.resize(to: .down, screenPct: -resizeAmt)
        }
        hotKeys.register(keyCode: kVK_UpArrow, modifierKeys: optionKey | cmdKey | shiftKey) {
            self.resize(to: .up, screenPct: -resizeAmt)
        }

        hotKeys.register(keyCode: kVK_ANSI_D, modifierKeys: optionKey | shiftKey) {
            log.debug("\(String(describing: self.tree.peek().root))")
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifierKeys: optionKey | shiftKey) {
            self.reload?(self)
        }

        hotKeys.register(keyCode: kVK_ANSI_X, modifierKeys: optionKey) {
            if let window = self.state.focusedWindow {
                self.addWindow(window)
            }
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifierKeys: optionKey) {
            self.tree.peek().refresh()
        }

        hotKeys.register(keyCode: kVK_ANSI_Minus, modifierKeys: optionKey) {
            self.split(.vertical)
        }
        hotKeys.register(keyCode: kVK_ANSI_Backslash, modifierKeys: optionKey) {
            self.split(.horizontal)
        }

        hotKeys.register(keyCode: kVK_ANSI_T, modifierKeys: optionKey) {
            self.stack(layout: .tabbed)
        }
        hotKeys.register(keyCode: kVK_ANSI_S, modifierKeys: optionKey) {
            self.stack(layout: .stacked)
        }
        hotKeys.register(keyCode: kVK_ANSI_E, modifierKeys: optionKey) {
            self.unstack()
        }

        hotKeys.register(keyCode: kVK_Return, modifierKeys: optionKey) {
            self.addNewWindows = !self.addNewWindows
        }
    }

    func addWindow(_ window: Window) {
        _ = addWindowReturningNode(window)
    }

    // For testing only.
    func addWindowReturningNode(_ window: Window) -> WindowNode? {
        if tree.peek().root.contains(window: window) {
            return nil
        }

        var node: WindowNode!
        tree.with { tree in
            if let focusNode = focus?.node,
               let parent = focusNode.base.parent {
                node = parent.createWindow(window, at: .after(focusNode))
            } else {
                node = tree.root.createWindow(window, at: .end)
            }

            // Question: Do we always want to focus new windows?
            node.selectGlobally()
            focus = Crawler(at: node.kind)
            raiseFocus()
        }

        return node
    }

    private func onWindowDestroyed(_ window: Window) {
        tree.with { tree in
            if let node = tree.find(window: window) {
                let parent = node.parent
                node.destroy()
                if node == focus?.node.base {
                    // TODO: Is this always correct? What if parent has no other
                    // children, or is culled?
                    focus = parent?.selection?.toCrawler()
                    raiseFocus()
                }
            }
        }
    }

    func moveFocus(_ direction: Direction) {
        guard let next = focus?.move(direction, leaf: .selected) else {
            return
        }
        focus = next

        next.node.base.selectGlobally()
        raiseFocus()
    }

    func focusParent() {
        guard let parent = focus?.node.base.parent else {
            return
        }
        focus = Crawler(at: parent)
    }

    func focusChild() {
        guard let child = focus?.node.containerNode?.selection else {
            return
        }
        focus = Crawler(at: child)
    }

    func moveFocusedNode(_ direction: Direction) {
        guard let node = focus?.node else {
            return
        }
        tree.with { tree in
            node.move(inDirection: direction)
        }
    }

    func resize(to direction: Direction, screenPct: Float) {
        guard let node = focus?.node else {
            return
        }
        tree.with { tree in
            node.resize(byScreenPercentage: screenPct, inDirection: direction)
        }
    }

    private func onFocusedWindowChanged(window: Window?) {
        // TODO: This can happen when a window is destroyed and the OS
        // automatically focuses another window from the same application. We
        // should ignore these events instead of letting them influence
        // selection.
        //
        // One way to do this is to simply add a delay on external events, but
        // this won't be as reliable. Another way is tracking our raise requests
        // and "locking" selection until they complete. This requires careful
        // error handling (what if the window we raise is destroyed first? what
        // if the request times out?)
        guard let window = window else { return }
        guard let node = tree.peek().find(window: window) else { return }
        focus = Crawler(at: node)
        node.selectGlobally()
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

    func split(_ layout: Layout) {
        if let node = self.focus?.node {
            putContainerAbove(node, layout: layout)
        } else {
            tree.peek().root.layout = layout
        }
    }

    func putContainerAbove(_ node: NodeKind, layout: Layout) {
        // FIXME: This modifies the tree without calling tree.with!
        // In this case, it does not affect sizing, but we need a more principled
        // approach here. Think Binder in rustc.
        if let parent = node.base.parent, parent.children.count == 1 {
            // This node already has a container around itself; just set the layout.
            // This won't affect sizes.
            parent.layout = layout
            return
        }

        node.node.insertParent(layout: layout)
    }

    /// Converts the parent of the current node to tabbed or stacked layout.
    func stack(layout: Layout) {
        assert(layout == .tabbed || layout == .stacked)
        guard let parent = self.focus?.node.parent else { return }
        tree.with { tree in
            if parent.layout == .horizontal || parent.layout == .vertical {
                parent.wmData.unstackLayout = parent.layout
            }
            parent.layout = layout
        }
    }

    /// Converts the parent of the current node back to the unstacked layout it
    /// was in previously.
    func unstack() {
        guard let parent = self.focus?.node.parent else { return }
        if parent.layout == .horizontal || parent.layout == .vertical {
            return
        }
        tree.with { tree in
            // This node must have had an unstacked layout previously.
            parent.layout = parent.wmData.unstackLayout!
        }
    }
}
