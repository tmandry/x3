import Cocoa
import Nimble
import Quick
import Swindler
@testable import x3

class CrawlerSpec: QuickSpec {
    override func spec() {
        var fakeApp: FakeApplication!
        var a, b, c, d, e: FakeWindow!

        func setup(screens: [FakeScreen]) {
            let state = createState(screens: screens)
            fakeApp = createApp(state)
            a = createWindowForApp(fakeApp, "A")
            b = createWindowForApp(fakeApp, "B")
            c = createWindowForApp(fakeApp, "C")
            d = createWindowForApp(fakeApp, "D")
            e = createWindowForApp(fakeApp, "E")
        }

        func testWithLayouts(horizontal: Layout, vertical: Layout) {
            context("with a single screen") {
                var tree: Tree!
                var root: ContainerNode { get { return tree.root } }

                beforeEach {
                    let screen = FakeScreen()
                    setup(screens: [screen])
                    tree = Tree(screen: screen.screen)
                }

                describe("Crawler") {
                    func checkMove(_ direction: Direction, leaf: Crawler.DescentStrategy,
                                from: FakeWindow, to: FakeWindow,
                                file: FileString = #file, line: UInt = #line) {
                        let crawler = Crawler(at: root.find(window: from.window)!)
                        let result = crawler.move(direction, leaf: leaf)?.node
                        expect(result, file: file, line: line).to(equal(
                            root.find(window: to.window)!.kind
                        ))
                    }

                    var child, grandchild: ContainerNode!
                    beforeEach {
                        root.makeWindow(a.window, at: .end)
                            .makeContainer(layout: vertical, at: .end) { n in
                                child = n
                                n.makeWindow(b.window, at: .end)
                                .makeWindow(c.window, at: .end)
                                .makeContainer(layout: horizontal, at: .end) { n in
                                    grandchild = n
                                    n.makeWindow(d.window, at: .end)
                                    .makeWindow(e.window, at: .end)
                                }
                            }
                    }

                    it("moves predictably") {
                        checkMove(.right, leaf: .selected, from: d, to: e)
                        checkMove(.up,    leaf: .selected, from: d, to: c)
                        checkMove(.left,  leaf: .selected, from: d, to: a)
                    }

                    it("follows selection path when DescentStrategy.selected is used") {
                        root.find(window: e.window)!.selectGlobally()
                        checkMove(.right, leaf: .selected, from: a, to: e)
                        root.find(window: c.window)!.selectGlobally()
                        checkMove(.right, leaf: .selected, from: a, to: c)
                    }

                    it("ascends") {
                        var crawl = Crawler(at: root.find(window: d.window)!)
                        crawl = crawl.ascend()!
                        expect(crawl.node) == grandchild.kind
                        crawl = crawl.ascend()!
                        expect(crawl.node) == child.kind
                        crawl = crawl.ascend()!
                        expect(crawl.node) == root.kind
                    }

                    it("doesn't move from the root node") {
                        let crawl = Crawler(at: root.kind)
                        expect(crawl.move(.down, leaf: .selected)?.node).to(beNil())
                    }
                }

                describe("NodeKind.move") {
                    it("moves within a container") {
                        var aNode, bNode, cNode: NodeKind!
                        root.makeWindow(a.window, at: .end) { aNode = $0.kind }
                            .makeWindow(b.window, at: .end) { bNode = $0.kind }
                            .makeWindow(c.window, at: .end) { cNode = $0.kind }

                        bNode.move(inDirection: .right)
                        expect(root.children) == [aNode, cNode, bNode]
                        cNode.move(inDirection: .left)
                        expect(root.children) == [cNode, aNode, bNode]

                        cNode.move(inDirection: .left)  // no-op
                        expect(root.children) == [cNode, aNode, bNode]
                        bNode.move(inDirection: .right)  // no-op
                        expect(root.children) == [cNode, aNode, bNode]

                        cNode.move(inDirection: .right)
                        expect(root.children) == [aNode, cNode, bNode]
                        bNode.move(inDirection: .left)
                        expect(root.children) == [aNode, bNode, cNode]
                    }

                    var aNode, bNode, cNode, dNode, eNode: NodeKind!
                    var leftChild, rightChild, grandChild: ContainerNode!
                    func makeNestedLayout(rightChild rcl: Layout, grandChild gcl: Layout) {
                        root.makeContainer(layout: horizontal) { n in
                            leftChild = n
                            n.makeWindow(a.window) { aNode = $0.kind }
                            .makeWindow(b.window) { bNode = $0.kind }
                        }.makeContainer(layout: rcl) { n in
                            rightChild = n
                            n.makeWindow(c.window) { cNode = $0.kind }
                            .makeContainer(layout: gcl) { n in
                                grandChild = n
                                n.makeWindow(d.window) { dNode = $0.kind }
                                .makeWindow(e.window) { eNode = $0.kind }
                            }
                        }
                        dNode.base.selectGlobally()
                    }

                    it("moves nodes between adjacent containers of same orientation") {
                        makeNestedLayout(rightChild: horizontal, grandChild: horizontal)

                        bNode.move(inDirection: .right)
                        expect(bNode.parent) == rightChild
                        expect(rightChild.children) == [bNode, cNode, grandChild.kind]
                        expect(leftChild.children) == [aNode]

                        bNode.move(inDirection: .left)
                        expect(bNode.parent) == leftChild
                        expect(rightChild.children) == [cNode, grandChild.kind]
                        expect(leftChild.children) == [aNode, bNode]
                    }

                    it("moves nodes between adjacent containers of different orientation") {
                        makeNestedLayout(rightChild: vertical, grandChild: horizontal)

                        // Since rightChild is now vertical and grandChild is part of the selection
                        // path, b will move into grandChild to the left of d.
                        bNode.move(inDirection: .right)
                        expect(bNode.parent) == grandChild
                        expect(grandChild.children) == [bNode, dNode, eNode]
                        expect(leftChild.children) == [aNode]

                        bNode.move(inDirection: .left)
                        expect(bNode.parent) == leftChild
                        expect(grandChild.children) == [dNode, eNode]
                        expect(leftChild.children) == [aNode, bNode]
                    }

                    it("moves to after the selection for destinations of different orientation") {
                        makeNestedLayout(rightChild: vertical, grandChild: vertical)

                        // grandChild is now vertical, too, so there's nothing to move to the left of.
                        // bNode will end up after the selected node, dNode.
                        bNode.move(inDirection: .right)
                        expect(bNode.parent) == grandChild
                        expect(grandChild.children) == [dNode, bNode, eNode]
                        expect(leftChild.children) == [aNode]

                        bNode.move(inDirection: .left)
                        expect(bNode.parent) == leftChild
                        expect(grandChild.children) == [dNode, eNode]
                        expect(leftChild.children) == [aNode, bNode]
                    }

                    it("moves container nodes within their container") {
                        makeNestedLayout(rightChild: horizontal, grandChild: horizontal)

                        grandChild.kind.move(inDirection: .left)
                        expect(grandChild.parent) == rightChild  // as before
                        expect(grandChild.children) == [dNode, eNode]  // as before
                        expect(rightChild.children) == [grandChild.kind, cNode]
                    }

                    it("moves container nodes to neighboring ancestor nodes") {
                        makeNestedLayout(rightChild: vertical, grandChild: horizontal)

                        grandChild.kind.move(inDirection: .left)
                        expect(grandChild.parent) == leftChild
                        expect(grandChild.children) == [dNode, eNode]  // as before
                    }

                    context("when moving perpendicular to its parent") {
                        it("moves nodes up to an ancestor and back down") {
                            root.makeWindow(a.window) { aNode = $0.kind }
                                .makeContainer(layout: vertical) { n in
                                    rightChild = n
                                    n.makeWindow(b.window) { bNode = $0.kind }
                                    .makeWindow(c.window) { cNode = $0.kind }
                                    .makeWindow(d.window) { dNode = $0.kind }
                                }

                            aNode.base.selectGlobally()
                            dNode.base.selectGlobally()

                            dNode.move(inDirection: .left)
                            expect(dNode.parent) == root
                            expect(root.children) == [aNode, dNode, rightChild.kind]

                            dNode.move(inDirection: .right)
                            expect(dNode.parent) == rightChild
                            expect(root.children) == [aNode, rightChild.kind]
                            expect(rightChild.children) == [bNode, cNode, dNode]

                            dNode.move(inDirection: .right)
                            expect(dNode.parent) == root
                            expect(root.children) == [aNode, rightChild.kind, dNode]

                            dNode.move(inDirection: .left)
                            expect(dNode.parent) == rightChild
                            expect(root.children) == [aNode, rightChild.kind]
                            expect(rightChild.children) == [bNode, cNode, dNode]
                        }
                    }

                    context("when moving parallel but outside its parent") {
                        it("moves nodes up to an ancestor and back down") {
                            root.makeWindow(a.window) { aNode = $0.kind }
                                .makeContainer(layout: horizontal) { n in
                                    rightChild = n
                                    n.makeWindow(b.window) { bNode = $0.kind }
                                    .makeWindow(c.window) { cNode = $0.kind }
                                    .makeWindow(d.window) { dNode = $0.kind }
                                }

                            aNode.base.selectGlobally()
                            dNode.base.selectGlobally()

                            bNode.move(inDirection: .left)
                            expect(bNode.parent) == root
                            expect(root.children) == [aNode, bNode, rightChild.kind]

                            bNode.move(inDirection: .right)
                            expect(bNode.parent) == rightChild
                            expect(root.children) == [aNode, rightChild.kind]
                            expect(rightChild.children) == [bNode, cNode, dNode]

                            dNode.move(inDirection: .right)
                            expect(dNode.parent) == root
                            expect(root.children) == [aNode, rightChild.kind, dNode]

                            dNode.move(inDirection: .left)
                            expect(dNode.parent) == rightChild
                            expect(root.children) == [aNode, rightChild.kind]
                            expect(rightChild.children) == [bNode, cNode, dNode]
                        }
                    }

                    context("when a window is the only child of its container") {
                        var aNode, bNode, cNode, dNode: NodeKind!
                        var parent, grandparent: ContainerNode!
                        beforeEach {
                            root
                                .makeWindow(a.window) { aNode = $0.kind }
                                .makeContainer(layout: vertical) { gp in
                                    grandparent = gp
                                    gp
                                        .makeWindow(b.window) { bNode = $0.kind }
                                        .makeContainer(layout: horizontal) { p in
                                            parent = p
                                            p.makeWindow(c.window) { cNode = $0.kind }
                                        }
                                        .makeWindow(d.window) { dNode = $0.kind }
                                }
                            _ = (aNode, bNode, cNode, dNode, parent, grandparent)
                            expect(grandparent.children) == [bNode, parent.kind, dNode]
                        }

                        it("removes its parent when moved up in the direction of its grandparent") {
                            cNode.move(inDirection: .up)
                            expect(grandparent.children) == [bNode, cNode, dNode]
                        }

                        it("removes its parent when moved down in the direction of its grandparent") {
                            cNode.move(inDirection: .down)
                            expect(grandparent.children) == [bNode, cNode, dNode]
                        }

                        it("removes its parent when destroyed") {
                            cNode.windowNode!.destroy()
                            expect(grandparent.children) == [bNode, dNode]
                        }
                    }

                    context("when no parent can support the move") {
                        context("with only one node") {
                            it("does nothing") {
                                var aNode: NodeKind!
                                let oldRoot = root
                                root.layout = horizontal
                                root.makeWindow(a.window) { aNode = $0.kind }
                                aNode.move(inDirection: .down)
                                expect(tree.root) == oldRoot
                                expect(aNode.parent) == oldRoot
                                expect(oldRoot.layout) == horizontal
                                expect(oldRoot.children) == [aNode]
                            }
                        }

                        context("with only two nodes") {
                            var oldRoot: ContainerNode!
                            var aNode, bNode: NodeKind!
                            beforeEach {
                                oldRoot = root
                                root.layout = horizontal
                                root.makeWindow(a.window) { aNode = $0.kind }
                                    .makeWindow(b.window) { bNode = $0.kind }
                            }

                            context("if the root has the same orientation as the move") {
                                it("does nothing") {
                                    bNode.move(inDirection: .right)
                                    expect(tree.root) == oldRoot
                                    expect(tree.root.layout) == horizontal
                                    expect(tree.root.children) == [aNode, bNode]
                                    expect(bNode.parent) == tree.root
                                }
                            }

                            context("if the root has a different orientation than the move") {
                                it("creates a new root and moves the node") {
                                    bNode.move(inDirection: .down)
                                    expect(tree.root.children) == [oldRoot.kind, bNode]
                                    expect(tree.root.layout) == .vertical
                                    expect(oldRoot.children) == [aNode]
                                    expect(aNode.parent) == oldRoot
                                    expect(bNode.parent) == tree.root
                                }
                            }
                        }

                        context("with many nodes") {
                            it("creates a new root and moves the node") {
                                let oldRoot = root
                                makeNestedLayout(rightChild: horizontal, grandChild: horizontal)
                                cNode.move(inDirection: .down)
                                expect(cNode.parent) == tree.root
                                expect(tree.root.layout) == .vertical
                                expect(tree.root.children) == [oldRoot.kind, cNode]
                            }
                        }
                    }
                }
            }
        }

        context("with horizontal, vertical layouts") {
            testWithLayouts(horizontal: .horizontal, vertical: .vertical)
        }

        context("with horizontal, stacked layouts") {
            testWithLayouts(horizontal: .horizontal, vertical: .stacked)
        }

        context("with tabbed, vertical layouts") {
            testWithLayouts(horizontal: .tabbed, vertical: .vertical)
        }

        context("with tabbed, stacked layouts") {
            testWithLayouts(horizontal: .tabbed, vertical: .stacked)
        }
    }
}
