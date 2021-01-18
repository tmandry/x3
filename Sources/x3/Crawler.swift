// - MARK: Crawler

enum Orientation {
    case horizontal
    case vertical
}

extension Layout {
    var orientation: Orientation {
        switch (self) {
        case .horizontal: return .horizontal
        case .vertical:   return .vertical
        case .tabbed:     return .horizontal
        case .stacked:    return .vertical
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
        switch (self) {
        case .up: return .vertical
        case .down: return .vertical
        case .left: return .horizontal
        case .right: return .horizontal
        }
    }

    var value: Int {
        switch (self) {
        case .up:    return -1
        case .down:  return +1
        case .left:  return -1
        case .right: return +1
        }
    }

    var opposite: Direction {
        switch (self) {
        case .up:    return .down
        case .down:  return .up
        case .left:  return .right
        case .right: return .left
        }
    }
}

/// A sort of generalized iterator which crawls the tree in all directions.
struct Crawler {
    private(set) var node: NodeKind

    init(at: NodeKind) {
        node = at
    }

    init(at: Node) {
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
        // Move in the desired direction.
        guard let (newContainer, index) = moveOne(node, direction, cursor: true) else {
            return nil
        }

        // Now descend the tree.
        var child = newContainer.children[index]
        switch leaf {
        case .selected:
            while let selection = child.selection {
                child = selection
            }
        }
        return Crawler(at: child)
    }
}

fileprivate func moveOne(_ node: NodeKind, _ direction: Direction, cursor: Bool)
-> (ContainerNode, Int)? {
    var child = node
    var container = child.base.parent
    guard container != nil else {
        // Nowhere to go from root (or deleted) element.
        return nil
    }

    // Walk up the tree until we're able to move in the right direction (or hit the end).
    let movingNode = cursor ? nil : node
    while container != nil && !canMove(direction, in: container!, from: child, movingNode) {
        child     = NodeKind.container(container!)
        container = container!.parent
    }

    guard let newContainer = container else {
        return nil
    }

    // Move over one in the requested direction.
    let index = newContainer.children.firstIndex(of: child)! + direction.value
    return (newContainer, index)
}

/// Checks whether we can move within `container` along direction `d` from `child`.
fileprivate func canMove(
    _ d: Direction, in container: ContainerNode, from child: NodeKind, _ movingNode: NodeKind?
) -> Bool {
    if container.layout.orientation != d.orientation {
        return false
    }
    if let node = movingNode, node != child {
        // The moving node descends from `child`, and therefore can move up to
        // `container` in its desired direction.
        return true
    }
    let curIndex = container.children.firstIndex(of: child)!
    let newIndex = curIndex + d.value
    return newIndex >= 0 && newIndex < container.children.count
}

extension NodeKind {
    func move(inDirection direction: Direction) {
        guard let (newContainer, point) = getMoveDestination(from: self, direction) else {
            // We couldn't find a move in this direction.
            return
        }
        if self.base.parent == nil {
            fatalError("cannot move root node")
        }
        self.node.reparent(newContainer, at: point)
    }

    private func getMoveDestination(from node: NodeKind,
                                    _ direction: Direction) -> (ContainerNode, InsertionPolicy)? {
        // Move in the desired direction.
        guard let (container, index) = moveOne(node, direction, cursor: false) else {
            return nil
        }
        if index < 0 {
            return (container, .begin)
        } else if index >= container.children.count {
            return (container, .end)
        } else {
            let child = container.children[index]

            // If we hit a leaf, we're done.
            guard case .container(let childContainer) = child else {
                // If we are moving node within the same container, then the point we want to insert
                // at is at index.
                if container == node.parent {
                    return (container, .at(index))
                }
                // Otherwise, we are moving up to an ancestor of `node`, and we want to insert it
                // BETWEEN its current ancestor and the node pointed by `child`.
                let point: InsertionPolicy = (direction.value < 0) ? .after(child) : .before(child)
                return (container, point)
            }

            return descendToDestination(childContainer, inDirection: direction.opposite)
        }
    }

    private func descendToDestination(_ container: ContainerNode,
                                      inDirection direction: Direction)
    -> (ContainerNode, InsertionPolicy) {
        var node = container.kind
        while case .container(let container) = node {
            node = firstChildInDirection(direction, container)!
        }

        // newContainer must be a descendant of container, so it has a parent.
        let newContainer = node.base.parent!

        var point: InsertionPolicy!
        if newContainer.layout.orientation == direction.orientation {
            point = (direction.value < 0) ? .begin : .end
        } else {
            if let selection = newContainer.selection {
                point = .after(selection)
            } else {
                // We only reach here if we encounter an empty container along the path.
                // Empty containers are usually culled; this is a bug.
                // TODO make a fatalError
                print("found empty container during move! tree: " +
                      String(describing: self.findRoot()))
                point = .begin
            }
        }
        return (newContainer, point)
    }

    // Returns the child to the farthest in direction `direction`. If this container
    // has a different orientation than `direction`, returns the selected child.
    private func firstChildInDirection(_ direction: Direction,
                                       _ container: ContainerNode) -> NodeKind? {
        if container.layout.orientation == direction.orientation {
            return (direction.value < 0) ? container.children.first : container.children.last
        } else {
            return container.selection
        }
    }
}
