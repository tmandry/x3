import Cocoa
import Swindler
import PromiseKit

enum Layout: String, Codable {
    case horizontal
    case vertical
    case stacked
    case tabbed
}

extension Layout {
    var isProportional: Bool {
        switch self {
            case .horizontal: return true
            case .vertical: return true
            case .stacked: return false
            case .tabbed: return false
        }
    }
}

let WINDOWS = CodingUserInfoKey(rawValue: "windows")!

enum DeserializeError: Error {
    case windowNotFound
}

class BoxedArray<T> {
    var array: [T] = []
    init(_ a: [T]) {
        array = a
    }
}

final class Tree {
    fileprivate(set) var root: ContainerNode
    var screen: Swindler.Screen! = nil

    init(screen: Swindler.Screen) {
        self.root = ContainerNode(.horizontal, parent: nil)
        setup(screen)
    }

    public static func inflate(
        from decoder: JSONDecoder, data: Data, screen: Swindler.Screen, state: Swindler.State
    ) throws -> Tree {
        // TODO: visible windows only
        decoder.userInfo[WINDOWS] = BoxedArray(state.knownWindows)
        let this = try decoder.decode(Tree.self, from: data)
        this.setup(screen)
        return this
    }

    fileprivate func setup(_ screen: Swindler.Screen) {
        self.screen = screen
        self.root.tree = self
        self.root.size = 1.0
    }

    func find(window: Swindler.Window) -> WindowNode? {
        return root.find(window: window)
    }

    func refresh() {
        var promises: [Promise<()>]? = nil
        root.delegate.refresh_(screen.applicationFrame, &promises)
    }

    func awaitRefresh() -> Promise<()> {
        var promises: [Promise<()>]? = []
        root.delegate.refresh_(screen.applicationFrame, &promises)
        return when(fulfilled: promises!)
    }
}

extension Tree: Codable {
    enum CodingKeys: CodingKey {
        case root
    }
}

class Node: Codable {
    fileprivate(set) var parent: ContainerNode?
    fileprivate var size: Float32
    private weak var delegate_: NodeDelegate?
    fileprivate var delegate: NodeDelegate {
        get {
            assert(delegate_ != nil, "nil delegate: \(self)")
            return delegate_!
        }
        set {
            assert(delegate_ == nil, "tried to set delegate to \(newValue) but it was already set to \(delegate_!)")
            delegate_ = newValue
        }
    }

    enum CodingKeys: CodingKey {
        case size
    }

    fileprivate init(parent: ContainerNode?) {
        self.parent = parent
        self.size = 0.0
    }

    var kind: NodeKind {
        delegate.getKind()
    }

    // TODO: remove all uses
    var base: Node { return self }
}

extension Node: Equatable {
    static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs === rhs
    }
}

extension Node {
    func reparent(_ newParent: ContainerNode, at point: InsertionPolicy) {
        guard let oldParent = base.parent else {
            fatalError("can't reparent a root or orphaned node: \(self)")
        }
        oldParent.removeChild(self.kind)
        self.base.parent = newParent
        newParent.addChild(self.kind, at: point)
        oldParent.cullIfEmpty()
    }

    fileprivate func setParentAfterDeserializing(_ newParent: ContainerNode) {
        assert(base.parent == nil)
        base.parent = newParent
    }

    /// Inserts a new parent above this node with the given layout.
    ///
    /// If used on an empty root node, the root node is replaced (culled).
    @discardableResult
    func insertParent(layout: Layout) -> ContainerNode {
        if let parent = parent {
            let container = parent.createContainer(layout: layout, at: .after(self.kind))
            reparent(container, at: .end)
            return container
        } else {
            // We are the root node. Create a new root.
            guard case .container(let oldRoot) = self.kind else {
                fatalError("Root node not a container")
            }
            guard let tree = oldRoot.tree else {
                fatalError("Root node has no reference to Tree, or Tree has been destroyed")
            }

            let newRoot = ContainerNode(layout, parent: nil)
            oldRoot.tree = nil
            self.parent = newRoot
            newRoot.addChild(self.kind, at: .end)
            tree.root = newRoot

            oldRoot.cullIfEmpty()
            return newRoot
        }
    }

    fileprivate func destroy_() {
        guard let parent = parent else {
            fatalError("cannot destroy root node")
        }
        parent.removeChild(self)
        parent.cullIfEmpty()
    }

    func contains(window: Swindler.Window) -> Bool {
        return self.kind.find(window: window) != nil
    }
}

extension Node {
    func find(window: Swindler.Window) -> WindowNode? {
        delegate.find_(window)
    }
    fileprivate func refresh(rect: CGRect, _ promises: inout [Promise<()>]?) {
        delegate.refresh_(rect, &promises)
    }
}

fileprivate protocol NodeDelegate: AnyObject {
    func getKind() -> NodeKind
    func find_(_: Swindler.Window) -> WindowNode?
    func refresh_(_: CGRect, _: inout [Promise<()>]?)
}

enum NodeKind {
    case container(ContainerNode)
    case window(WindowNode)

    var base: Node {
        switch self {
        case .container(let node):
            return node
        case .window(let node):
            return node
        }
    }

    // TODO: remove all uses
    var node: Node { return base }

    var windowNode: WindowNode? {
        switch self {
        case .container(_):
            return nil
        case .window(let node):
            return node
        }
    }

    var containerNode: ContainerNode? {
        switch self {
        case .container(let node):
            return node
        case .window(_):
            return nil
        }
    }
}

extension NodeKind {
    func find(window: Swindler.Window) -> WindowNode? {
        self.base.find(window: window)
    }
    fileprivate func refresh(rect: CGRect, _ promises: inout [Promise<()>]?) {
        self.base.refresh(rect: rect, &promises)
    }
}

extension NodeKind: Equatable {
    static func == (lhs: NodeKind, rhs: NodeKind) -> Bool {
        return lhs.base == rhs.base
    }
}

extension NodeKind {
    var parent: ContainerNode? {
        return base.parent
    }

    func findRoot() -> ContainerNode {
        var node = self
        while let ancestor = node.base.parent?.kind {
            node = ancestor
        }
        guard case .container(let root) = node else {
            fatalError("found non-container node with no parent")
        }
        return root
    }
}

extension NodeKind: Encodable {
    enum CodingKeys: CodingKey {
        case container
        case window
    }
    func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .container(let node):
            try object.encode(node, forKey: .container)
        case .window(let node):
            try object.encode(node, forKey: .window)
        }
    }
}

extension NodeKind: Decodable {
    init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let node = try object.decode(ContainerNode.self, forKey: .container)
            self = .container(node)
        } catch {
            let node = try object.decode(WindowNode.self, forKey: .window)
            self = .window(node)
        }
    }
}

enum InsertionPolicy {
    case begin
    case end
    case before(NodeKind)
    case after(NodeKind)
    case at(Int)
}

final class ContainerNode: Node {
    var layout: Layout
    private(set) var children: [NodeKind]
    var wmData: ContainerNodeWmData = ContainerNodeWmData()
    fileprivate var selectionData: SelectionData = initSelectionData()

    // Only the root node has a reference to the tree.
    fileprivate weak var tree: Tree?

    fileprivate init(_ type: Layout, parent: ContainerNode?) {
        layout = type
        children = []
        super.init(parent: parent)
        super.delegate = self
    }

    private enum CodingKeys: CodingKey {
        case layout, children, wmData, selectionData
    }

    required init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: CodingKeys.self)
        layout = try object.decode(Layout.self, forKey: .layout)
        children = try object.decode([NodeKind].self, forKey: .children)
        wmData = try object.decode(ContainerNodeWmData.self, forKey: .wmData)
        selectionData = try object.decode(SelectionData.self, forKey: .selectionData)
        try super.init(from: try object.superDecoder())
        super.delegate = self
        for child in children {
            child.node.setParentAfterDeserializing(self)
        }
    }

    override func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: CodingKeys.self)
        try super.encode(to: object.superEncoder())
        try object.encode(layout, forKey: .layout)
        try object.encode(children, forKey: .children)
        try object.encode(wmData, forKey: .wmData)
        try object.encode(selectionData, forKey: .selectionData)
    }

    /// Destroys this node and all of its children and removes them from the tree.
    func destroyAll() {
        destroy_()
    }
}

extension ContainerNode: NodeDelegate {
    fileprivate func getKind() -> NodeKind { .container(self) }
}

final class WindowNode: Node {
    let window: Swindler.Window

    fileprivate init(_ window: Swindler.Window, parent: ContainerNode?) {
        self.window = window
        super.init(parent: parent)
        super.delegate = self
    }

    required init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: CodingKeys.self)
        let windows = decoder.userInfo[WINDOWS] as! BoxedArray<Swindler.Window>
        window = try WindowNode.getWindow(object, windows)
        try super.init(from: object.superDecoder())
        super.delegate = self
    }

    private static func getWindow(
        _ object: KeyedDecodingContainer<CodingKeys>,
        _ windows: BoxedArray<Swindler.Window>
    ) throws -> Swindler.Window {
        let pid = try object.decode(pid_t.self, forKey: .pid)
        let frame = try object.decode(CGRect.self, forKey: .frame)
        let title = try object.decode(String.self, forKey: .title)
        guard let index = windows.array.firstIndex(where: { window in
            pid == window.application.processIdentifier &&
            frame == window.frame.value &&
            title == window.title.value
        }) else {
            log.debug(
                "failed to find window pid=\(pid) frame=\(String(describing: frame)) title=\(title)"
            )
            throw DeserializeError.windowNotFound
        }
        let window = windows.array[index]
        windows.array.remove(at: index)
        return window
    }

    private enum CodingKeys: CodingKey {
        case pid, frame, title
    }
    override func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: CodingKeys.self)
        try super.encode(to: object.superEncoder())
        try object.encode(window.application.processIdentifier, forKey: .pid)
        try object.encode(window.frame.value, forKey: .frame)
        try object.encode(window.title.value, forKey: .title)
    }

    /// Destroys this node and removes it from the parent.
    func destroy() {
        destroy_()
    }
}

extension WindowNode: NodeDelegate {
    fileprivate func getKind() -> NodeKind { .window(self) }
}

private extension String {
    func truncate(length: Int, trailing: String = "…") -> String {
        if self.count > length {
            return String(self.prefix(length)) + trailing
        } else {
            return self
        }
    }
}
extension ContainerNode: CustomDebugStringConvertible {
    var debugDescription: String {
        return "\(layout)(size=\(size), \(children.map{$0.node}))"
    }
}
extension WindowNode: CustomDebugStringConvertible {
    var debugDescription: String {
        return "window(\(window.title.value.truncate(length: 30)), size=\(size))"
    }
}

// - MARK: Children
extension ContainerNode {
    @discardableResult
    func createContainer(layout: Layout, at: InsertionPolicy) -> ContainerNode {
        let node = ContainerNode(layout, parent: self)
        let index = indexForPolicy(at)
        children.insert(.container(node), at: index)
        onNewNode(index: index)
        return node
    }

    @discardableResult
    func createContainer(layout: Layout,
                         at: InsertionPolicy,
                         _ f: (ContainerNode) -> ())
    -> ContainerNode {
        let child = createContainer(layout: layout, at: at)
        f(child)
        return child
    }

    @discardableResult
    func createWindow(_ window: Swindler.Window, at: InsertionPolicy) -> WindowNode {
        let node = WindowNode(window, parent: self)
        let index = indexForPolicy(at)
        children.insert(.window(node), at: index)
        onNewNode(index: index)
        return node
    }

    fileprivate func addChild(_ child: NodeKind, at: InsertionPolicy) {
        assert(child.parent == self)
        let index = indexForPolicy(at)
        children.insert(child, at: index)
        onNewNode(index: index)
    }

    private func indexForPolicy(_ policy: InsertionPolicy) -> Int {
        switch policy {
        case .begin:
            return 0
        case .end:
            return children.endIndex
        case .before(let node):
            guard let index = children.firstIndex(of: node) else {
                fatalError("requested to insert node before a non-existent child")
            }
            return index
        case .after(let node):
            guard let index = children.firstIndex(of: node) else {
                fatalError("requested to insert node after a non-existent child")
            }
            return index + 1
        case .at(let index):
            return index
        }
    }

    // TODO: Make it an error to call with a node who isn't our child
    fileprivate func removeChild(_ node: Node) {
        guard let index = children.firstIndex(where: {$0.node === node}) else {
            return
        }
        children.remove(at: index)

        onRemoveNode()
    }

    fileprivate func removeChild(_ node: NodeKind) {
        removeChild(node.base)
    }

    // Remove ourselves from the tree, if empty.
    fileprivate func cullIfEmpty() {
        if children.isEmpty, let parent = parent {
            parent.removeChild(self)

            // This isn't strictly necessary, but should help to prevent bugs.
            self.parent = nil
        }
    }

    private func onNewNode(index: Int) {
        onNewNodeAdjustSize(index: index)
        onNewNodeUpdateSelection(index: index)
    }

    private func onRemoveNode() {
        onRemoveNodeAdjustSize()
    }
}
extension ContainerNode {
    func find_(_ window: Swindler.Window) -> WindowNode? {
        return children.compactMap({$0.find(window: window)}).first
    }
}
extension WindowNode {
    func find_(_ window: Swindler.Window) -> WindowNode? {
        if self.window == window {
            return self
        }
        return nil
    }
}

// - MARK: Size

extension ContainerNode {
    fileprivate func onNewNodeAdjustSize(index: Int) {
        let newSize: Float = 1.0 / Float(children.count)
        let scale = Float(children.count - 1) / Float(children.count)
        for (i, child) in children.enumerated() {
            if i != index {
                child.base.size *= scale
            }
        }
        children[index].base.size = newSize
        check()
    }
    fileprivate func onRemoveNodeAdjustSize() {
        if children.count == 0 {
            return
        }
        let scale = Float(children.count + 1) / Float(children.count)
        for child in children {
            child.base.size *= scale
        }
        check()
    }
    private func check() {
        // sizes should all sum to 1
        assert(children.reduce(0.0){$0 + $1.base.size}.distance(to: 1.0) < 0.01)
    }

    func refresh_(_ rect: CGRect, _ promises: inout [Promise<()>]?) {
        var start: Float = 0.0
        for child in children {
            let end = start + child.base.size
            child.refresh(rect: rectForSlice(whole: rect, start, end), &promises)
            start = end
        }
    }
    private func rectForSlice(whole: CGRect, _ start: Float, _ end: Float) -> CGRect {
        let start = CGFloat(start)
        let end   = CGFloat(end)
        switch layout {
        case .horizontal:
            return CGRect(x: (whole.minX + start * whole.width).rounded(),
                          y: whole.minY,
                          width: ((end - start) * whole.width).rounded(),
                          height: whole.height)
        case .vertical:
            // Note that vertical containers go down, while macOS y coordinates go up, so we flip
            // our slice here.
            return CGRect(x: whole.minX,
                          y: (whole.minY + (1.0 - end) * whole.height).rounded(),
                          width: whole.width,
                          height: ((end - start) * whole.height).rounded())
        case .tabbed:
            return whole
        case .stacked:
            return whole
        }
    }
}

extension WindowNode {
    func refresh_(_ rect: CGRect, _ promises: inout [Promise<()>]?) {
        // log.debug("RESIZING window to \(rect.rounded()) (\(rect)")
        let rect = rect.rounded()
        let promise = window.frame.set(rect)
        if promises != nil {
            promises!.append(promise.map({_ in ()}))
        }
    }
}

private extension CGRect {
    func rounded() -> CGRect {
        return CGRect(x: self.minX.rounded(), y: self.minY.rounded(),
                      width: self.width.rounded(), height: self.height.rounded())
    }
}

extension NodeKind {
    @discardableResult
    public func resize(byScreenPercentage screenPct: Float, inDirection direction: Direction)
    -> Bool {
        var resizingNode = self
        while !canResize(direction, from: resizingNode) {
            guard let parent = resizingNode.parent else {
                return false
            }
            resizingNode = parent.kind
        }
        let parent = resizingNode.parent!

        let sibling = parent.children[
            parent.children.firstIndex(of: resizingNode)! + direction.value
        ]

        // Calculate the "exchange rate" betwen our parent node's size ratios
        // and the overall screen ratio.
        //
        // To do this we want to look at each ancestor node wrt its parent; if
        // it is in a container splitting sizes the same way we're resizing,
        // factor its relative size into the overall ratio.
        var exchangeRate = 1.0
        var ancestor = Optional(parent)
        while let cur = ancestor {
            if let curParent = cur.parent,
                curParent.layout.orientation == direction.orientation &&
                curParent.layout.isProportional
            {
                exchangeRate *= Double(cur.size)
            }
            ancestor = cur.parent
        }
        let amountToTake = screenPct / Float(exchangeRate)

        // Only one of these can be false, depending on the sign of amountToTake.
        if sibling.base.size <= amountToTake || resizingNode.base.size <= -amountToTake {
            return false
        }

        sibling.base.size -= amountToTake
        resizingNode.base.size += amountToTake
        return true
    }
}

private func canResize(_ direction: Direction, from child: NodeKind) -> Bool {
    // This is the same predicate as whether we can move a cursor in the desired
    // direction, except we also need the parent layout to be proportional.
    guard let parent = child.parent else {
        return false
    }
    if !parent.layout.isProportional {
        return false
    }
    return canMove(direction, from: child, nil)
}

// - MARK: Selection
// Every non-empty container has a selected node. This node is used, for
// example, in determining which child node to move to during a keyboard motion.
//
// All container nodes have a selected node, but may not themselves be selected.
// In this case, we say the selected node is "locally selected". If the
// selection path from the root of the tree includes a node, we say it is
// "globally selected."
//
// If the selected node is removed, the node after it is selected. If there
// is no node after the removed node, the node before it is selected.
// This is easily accomplished with a simple integer index.

fileprivate typealias SelectionData = Int

fileprivate func initSelectionData() -> SelectionData { return 0 }

extension ContainerNode {
    /// Returns the selected node of this container.
    ///
    /// There is always a selected node, unless the container is empty.
    var selection: NodeKind? {
        get {
            if children.isEmpty {
                return nil
            }
            return children[min(selectionData, children.count - 1)]
        }
    }

    func onNewNodeUpdateSelection(index: Int) {
        if index <= selectionData {
            selectionData += 1
        }
    }

    // FIXME: We need to update the index anytime a child node is added or
    // removed before the selected node.
}

extension Node {
    /// Whether this node is the locally selected node of its parent.
    ///
    /// Note that this does *NOT* indicate whether the node is globally selected.
    var isSelected: Bool {
        guard let parent = parent else {
            // By convention, the root node is never considered selected.
            return false
        }
        // We know our parent has at least one child, so it must have a selection.
        return parent.selection!.base == self
    }

    /// Selects this node locally (within its parent).
    func selectLocally() {
        guard let parent = parent else {
            fatalError("cannot select root node")
        }
        parent.selectionData = parent.children.firstIndex(where: {$0.base == self})!
    }

    /// Selects this node globally (this node and all its ancestors are selected).
    func selectGlobally() {
        var node = self
        while let parent = node.parent {
            node.selectLocally()
            node = parent
        }
    }
}

extension NodeKind {
    var selection: NodeKind? {
        switch self {
        case .container(let c):
            return c.selection
        case .window:
            return nil
        }
    }
}
