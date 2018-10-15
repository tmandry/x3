// - MARK: Crawler

enum Orientation {
    case horizontal
    case vertical
}

extension Layout {
    var orientation: Orientation {
        get {
            switch (self) {
            case .horizontal: return .horizontal
            case .vertical:   return .vertical
            case .stacked:    return .vertical
            }
        }
    }
}

enum Direction {
    case up
    case down
    case left
    case right
}

extension Direction {
    var orientation: Orientation {
        get {
            switch (self) {
            case .up: return .vertical
            case .down: return .vertical
            case .left: return .horizontal
            case .right: return .horizontal
            }
        }
    }

    var value: Int {
        get {
            switch (self) {
            case .up:    return -1
            case .down:  return +1
            case .left:  return -1
            case .right: return +1
            }
        }
    }
}

/// A sort of generalized iterator which crawls the tree in all directions.
struct Crawler {
    var node: NodeKind

    init(at: NodeKind) {
        node = at
    }

    init(at: NodeType) {
        self.init(at: at.kind)
    }

    /// Moves the crawler to the current node's parent.
    func ascend() -> Crawler? {
        guard let parent = node.base.parent else {
            return nil
        }
        return Crawler(at: parent.kind)
    }

    /// Describes how to select a leaf node in the tree after moving.
    enum DescentStrategy {
        /// Follow the selection path.
        ///
        /// For example, `move(.right, leaf: .selected)` will find the subtree
        /// directly to the right of the current node, and pick its selected
        /// leaf node.
        case selected
        // TODO: nearest
    }

    /// Moves the crawler in the cardinal direction specified.
    ///
    /// Selects a leaf node according to the requested `DescentStrategy`.
    func move(_ direction: Direction, leaf: DescentStrategy) -> Crawler? {
        var child = node
        var container = child.base.parent
        guard container != nil else {
            // Nowhere to go from root (or deleted) element.
            return nil
        }

        // Walk up the tree until we're able to move in the right direction (or hit the end).
        while container != nil && !canMove(direction, in: container!, from: child) {
            child     = NodeKind.container(container!)
            container = container!.parent
        }

        guard let newContainer = container else {
            return nil
        }

        // Move over one in the requested direction.
        let index = newContainer.children.index(of: child)! + direction.value

        // Now descend the tree.
        child = newContainer.children[index]
        switch leaf {
        case .selected:
            while let selection = child.selection {
                child = selection
            }
        }
        return Crawler(at: child)
    }

    /// Checks whether we can move within `container` along direction `d` from `child`.
    private func canMove(_ d: Direction, in container: ContainerNode, from child: NodeKind) -> Bool {
        if container.layout.orientation != d.orientation {
            return false
        }
        let curIndex = container.children.index(of: child)!
        let newIndex = curIndex + d.value
        return newIndex >= 0 && newIndex < container.children.count
    }
}
