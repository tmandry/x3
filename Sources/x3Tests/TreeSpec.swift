import Cocoa
import Nimble
import Quick
import Swindler
import PromiseKit
@testable import x3

private func r(x: Int, y: Int, w: Int, h: Int) -> CGRect {
    return CGRect(x: x, y: y, width: w, height: h)
}

class TreeSpec: QuickSpec {
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

        context("with a single screen") {
            var screen: FakeScreen!
            var tree: Tree!

            var root: ContainerNode { get { return tree.root } }

            beforeEach {
                screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 2000, height: 1060),
                                    menuBarHeight: 10,
                                    dockHeight: 50)
                expect(screen.screen.applicationFrame) == CGRect(x: 0, y: 50, width: 2000, height:
                                                                 1000)
                setup(screens: [screen])
                tree = Tree(screen: screen.screen)
            }

            describe("insertParent") {
                context("with a populated tree") {
                    var root, middle: ContainerNode!
                    var aNode, bNode, cNode: NodeKind!
                    beforeEach {
                        root = tree.root
                        aNode = root.createWindow(a.window, at: .end).kind
                        middle = tree.root.createContainer(layout: .vertical, at: .end)
                        bNode = middle.createWindow(b.window, at: .end).kind
                        cNode = middle.createWindow(c.window, at: .end).kind
                    }

                    it("works for middle nodes") {
                        let inserted = middle.insertParent(layout: .vertical)
                        expect(tree.root) == root
                        expect(root.children) == [aNode, inserted.kind]
                        expect(inserted.children) == [middle.kind]
                        expect(middle.parent) == inserted
                        expect(middle.children) == [bNode, cNode]
                    }

                    it("works for leaf nodes") {
                        let inserted = bNode.node.insertParent(layout: .vertical)
                        expect(tree.root) == root
                        expect(root.children) == [aNode, middle.kind]
                        expect(middle.children) == [inserted.kind, cNode]
                        expect(inserted.children) == [bNode]
                        expect(bNode.parent) == inserted
                    }

                    it("works for the root node") {
                        let inserted = root.insertParent(layout: .vertical)
                        expect(tree.root) == inserted
                        expect(root.parent) == inserted
                        expect(inserted.children) == [root.kind]
                        expect(root.children) == [aNode, middle.kind]
                        expect(middle.children) == [bNode, cNode]
                    }
                }

                context("with an empty tree") {
                    it("replaces and culls the current root node") {
                        let root = tree.root
                        let inserted = root.insertParent(layout: .vertical)
                        expect(tree.root) == inserted
                        expect(inserted.children) == []
                    }
                }
            }

            it("lays out windows horizontally by default") {
                return firstly { () -> Promise<()> in
                    tree.root.createWindow(a.window, at: .end)
                    tree.root.createWindow(b.window, at: .end)
                    return tree.awaitRefresh()
                }.done {
                    expect(a.frame).to(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).to(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))
                }.then { () -> Promise<()> in
                    tree.root.createWindow(c.window, at: .end)
                    return tree.awaitRefresh()
                }.done {
                    expect(a.frame).to(equal(r(x: 0,    y: 50, w: 667, h: 1000)))
                    expect(b.frame).to(equal(r(x: 667,  y: 50, w: 667, h: 1000)))
                    expect(c.frame).to(equal(r(x: 1333, y: 50, w: 667, h: 1000)))
                }
            }

            it("removes windows when they are destroyed") { () -> Promise<()> in
                let anode = tree.root.createWindow(a.window, at: .end)
                let bnode = tree.root.createWindow(b.window, at: .end)
                let cnode = tree.root.createWindow(c.window, at: .end)
                return firstly { () -> Promise<()> in
                    return tree.awaitRefresh()
                }.then { () -> Promise<()> in
                    bnode.destroy()
                    return tree.awaitRefresh()
                }.done {
                    expect(a.frame).to(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(c.frame).to(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))
                }.then { () -> Promise<()> in
                    anode.destroy()
                    return tree.awaitRefresh()
                }.done {
                    expect(c.frame).to(equal(r(x: 0, y: 50, w: 2000, h: 1000)))
                }.then { () -> Promise<()> in
                    // Test that we don't crash upon destroying the last window.
                    cnode.destroy()
                    return tree.awaitRefresh()
                }
            }

            it("allows nesting a horizontal container inside horizontal") {
                return firstly { () -> Promise<()> in
                    tree.root.createWindow(a.window, at: .end)
                    let child = tree.root.createContainer(layout: .horizontal, at: .end)
                    child.createWindow(b.window, at: .end)
                    child.createWindow(c.window, at: .end)

                    return tree.awaitRefresh()
                }.done {
                    expect(a.frame).to(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).to(equal(r(x: 1000, y: 50, w: 500,  h: 1000)))
                    expect(c.frame).to(equal(r(x: 1500, y: 50, w: 500,  h: 1000)))
                }
            }

            context("when a vertical container is nested inside a horizontal") {
                var child: ContainerNode!
                var dnode: WindowNode!

                beforeEach {
                    tree.root.createWindow(a.window, at: .end)
                    child = tree.root.createContainer(layout: .vertical, at: .end)
                    child.createWindow(b.window, at: .end)
                    child.createWindow(c.window, at: .end)
                    dnode = child.createWindow(d.window, at: .end)
                    waitUntil { done in
                        tree.awaitRefresh().done { done() }.cauterize()
                    }
                }

                it("sizes windows correctly") {
                    expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                    expect(b.frame).to(equal(r(x: 1000, y: 717, w: 1000, h: 333)))
                    expect(c.frame).to(equal(r(x: 1000, y: 383, w: 1000, h: 333)))
                    expect(d.frame).to(equal(r(x: 1000, y: 50,  w: 1000, h: 333)))
                }

                it("correctly resizes when windows are moved") {
                    return firstly { () -> Promise<()> in
                        dnode.reparent(tree.root, at: .end)
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 667, h: 1000)))
                        expect(b.frame).to(equal(r(x: 667,  y: 550, w: 667, h: 500)))
                        expect(c.frame).to(equal(r(x: 667,  y: 50,  w: 667, h: 500)))
                        expect(d.frame).to(equal(r(x: 1333, y: 50,  w: 667, h: 1000)))
                    }
                }
            }

            func testTabbedOrStacked(_ layout: Layout) -> Promise<()> {
                return firstly { () -> Promise<()> in
                    tree.root.createWindow(a.window, at: .end)
                    let parent = tree.root.createContainer(layout: layout, at: .end)
                    parent.createWindow(b.window, at: .end)
                    parent.createWindow(c.window, at: .end)
                    let childContainer = parent.createContainer(layout: .vertical, at: .end)
                    childContainer.createWindow(d.window, at: .end)
                    childContainer.createWindow(e.window, at: .end)
                    return tree.awaitRefresh()
                }.done {
                    expect(a.frame).to(equal(r(x: 0,    y:   50, w: 1000, h: 1000)))
                    expect(b.frame).to(equal(r(x: 1000, y:   50, w: 1000, h: 1000)))
                    expect(c.frame).to(equal(r(x: 1000, y:   50, w: 1000, h: 1000)))
                    expect(d.frame).to(equal(r(x: 1000, y:  550, w: 1000, h:  500)))
                    expect(e.frame).to(equal(r(x: 1000, y:   50, w: 1000, h:  500)))
                }
            }

            describe("stacked layout") {
                it("makes all child nodes use the full parent rect") {
                    testTabbedOrStacked(.stacked)
                }
            }

            describe("tabbed layout") {
                it("makes all child nodes use the full parent rect") {
                    testTabbedOrStacked(.tabbed)
                }
            }

            context("when containers are nested 3 deep") {
                var child, grandchild: ContainerNode!

                beforeEach {
                    tree.root.createWindow(a.window, at: .end)
                    child = tree.root.createContainer(layout: .vertical, at: .end)
                    child.createWindow(b.window, at: .end)
                    grandchild = child.createContainer(layout: .horizontal, at: .end)
                    grandchild.createWindow(c.window, at: .end)
                    grandchild.createWindow(d.window, at: .end)
                    waitUntil { done in
                        tree.awaitRefresh().done { done() }.cauterize()
                    }
                }

                it("sizes windows correctly") {
                    expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                    expect(b.frame).to(equal(r(x: 1000, y: 550, w: 1000, h: 500)))
                    expect(c.frame).to(equal(r(x: 1000, y: 50,  w: 500,  h: 500)))
                    expect(d.frame).to(equal(r(x: 1500, y: 50,  w: 500,  h: 500)))
                }

                it("correctly resizes when a container is moved") {
                    return firstly { () -> Promise<()> in
                        // Note: in this case, `child` will end up having only one child window (b).
                        grandchild.reparent(tree.root, at: .end)
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 667, h: 1000)))
                        expect(b.frame).to(equal(r(x: 667,  y: 50,  w: 667, h: 1000)))
                        expect(c.frame).to(equal(r(x: 1333, y: 50,  w: 334, h: 1000)))
                        expect(d.frame).to(equal(r(x: 1667, y: 50,  w: 334, h: 1000)))
                    }
                }
            }

            describe("resize") {
                var child, grandchild: ContainerNode!
                var aNode, bNode, cNode, dNode, eNode: WindowNode!
                beforeEach {
                    root.makeWindow(a.window, at: .end) { aNode = $0 }
                        .makeContainer(layout: .vertical, at: .end) { n in
                            child = n
                            n.makeWindow(b.window, at: .end) { bNode = $0 }
                             .makeWindow(c.window, at: .end) { cNode = $0 }
                             .makeContainer(layout: .horizontal, at: .end) { n in
                                 grandchild = n
                                 n.makeWindow(d.window, at: .end) { dNode = $0 }
                                  .makeWindow(e.window, at: .end) { eNode = $0 }
                             }
                        }
                    _ = (aNode, bNode, cNode, dNode, eNode)

                    waitUntil { done in
                        tree.awaitRefresh().done {
                            expectStartingPoint()
                            done()
                        }.cauterize()
                    }
                }

                func expectStartingPoint() {
                    expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                    expect(b.frame).to(equal(r(x: 1000, y: 717, w: 1000, h:  333)))
                    expect(c.frame).to(equal(r(x: 1000, y: 383, w: 1000, h:  333)))
                    expect(d.frame).to(equal(r(x: 1000, y: 50,  w:  500, h:  333)))
                    expect(e.frame).to(equal(r(x: 1500, y: 50,  w:  500, h:  333)))
                }

                it("works for growing and shrinking") { () -> Promise<()> in
                    return firstly { () -> Promise<()> in
                        expect(aNode.kind.resize(byScreenPercentage: 0.01, inDirection: .right)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1020, h: 1000)))
                        expect(b.frame).to(equal(r(x: 1020, y: 717, w:  980, h:  333)))
                        expect(c.frame).to(equal(r(x: 1020, y: 383, w:  980, h:  333)))
                        expect(d.frame).to(equal(r(x: 1020, y: 50,  w:  490, h:  333)))
                        expect(e.frame).to(equal(r(x: 1510, y: 50,  w:  490, h:  333)))
                    }.then { () -> Promise<()> in
                        expect(aNode.kind.resize(byScreenPercentage: -0.01, inDirection: .right)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expectStartingPoint()
                    }
                }

                it("works for container node") {
                    return firstly { () -> Promise<()> in
                        expect(child.kind.resize(byScreenPercentage: 0.01, inDirection: .left)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x:    0, y: 50,  w:  980, h: 1000)))
                        expect(b.frame).to(equal(r(x:  980, y: 717, w: 1020, h:  333)))
                        expect(c.frame).to(equal(r(x:  980, y: 383, w: 1020, h:  333)))
                        expect(d.frame).to(equal(r(x:  980, y: 50,  w:  510, h:  333)))
                        expect(e.frame).to(equal(r(x: 1490, y: 50,  w:  510, h:  333)))
                    }
                }

                it("does nothing when no ancestors are oriented in the requested direction") {
                    return firstly { () -> Promise<()> in
                        expect(aNode.kind.resize(byScreenPercentage: 0.01, inDirection: .down)) == false
                        return tree.awaitRefresh()
                    }.done {
                        expectStartingPoint()
                    }
                }

                it("does nothing when running into the edge of the screen") {
                    return firstly { () -> Promise<()> in
                        expect(aNode.kind.resize(byScreenPercentage: 0.01, inDirection: .left)) == false
                        return tree.awaitRefresh()
                    }.done {
                        expectStartingPoint()
                    }
                }

                it("does nothing when it can't satisfy the requested size") {
                    return firstly { () -> Promise<()> in
                        expect(cNode.kind.resize(byScreenPercentage:  0.50, inDirection: .up)) == false
                        return tree.awaitRefresh()
                    }.done {
                        expectStartingPoint()
                    }.then { () -> Promise<()> in
                        expect(cNode.kind.resize(byScreenPercentage: -0.50, inDirection: .up)) == false
                        return tree.awaitRefresh()
                    }.done {
                        expectStartingPoint()
                    }
                }

                it("works for nested middle node") {
                    return firstly { () -> Promise<()> in
                        expect(cNode.kind.resize(byScreenPercentage: 0.01, inDirection: .up)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                        expect(b.frame).to(equal(r(x: 1000, y: 727, w: 1000, h:  323)))
                        expect(c.frame).to(equal(r(x: 1000, y: 383, w: 1000, h:  343)))
                        expect(d.frame).to(equal(r(x: 1000, y: 50,  w:  500, h:  333)))
                        expect(e.frame).to(equal(r(x: 1500, y: 50,  w:  500, h:  333)))
                    }.then { () -> Promise<()> in
                        expect(cNode.kind.resize(byScreenPercentage: 0.01, inDirection: .down)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                        expect(b.frame).to(equal(r(x: 1000, y: 727, w: 1000, h:  323)))
                        expect(c.frame).to(equal(r(x: 1000, y: 373, w: 1000, h:  353)))
                        expect(d.frame).to(equal(r(x: 1000, y: 50,  w:  500, h:  323)))
                        expect(e.frame).to(equal(r(x: 1500, y: 50,  w:  500, h:  323)))
                    }
                }

                it("works for node whose immediate parent is not oriented in the requested direction") {
                    return firstly { () -> Promise<()> in
                        expect(dNode.kind.resize(byScreenPercentage: 0.01, inDirection: .up)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                        expect(b.frame).to(equal(r(x: 1000, y: 717, w: 1000, h:  333)))
                        expect(c.frame).to(equal(r(x: 1000, y: 393, w: 1000, h:  323)))
                        expect(d.frame).to(equal(r(x: 1000, y: 50,  w:  500, h:  343)))
                        expect(e.frame).to(equal(r(x: 1500, y: 50,  w:  500, h:  343)))
                    }
                }

                it("picks an ancestor which has room for resizing") {
                    return firstly { () -> Promise<()> in
                        expect(dNode.kind.resize(byScreenPercentage: 0.01, inDirection: .left)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x:    0, y: 50,  w:  980, h: 1000)))
                        expect(b.frame).to(equal(r(x:  980, y: 717, w: 1020, h:  333)))
                        expect(c.frame).to(equal(r(x:  980, y: 383, w: 1020, h:  333)))
                        expect(d.frame).to(equal(r(x:  980, y: 50,  w:  510, h:  333)))
                        expect(e.frame).to(equal(r(x: 1490, y: 50,  w:  510, h:  333)))
                    }
                }

                it("behaves correctly with tabbed and stacked nodes") {
                    return firstly { () -> Promise<()> in
                        grandchild.layout = .tabbed
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                        expect(b.frame).to(equal(r(x: 1000, y: 717, w: 1000, h:  333)))
                        expect(c.frame).to(equal(r(x: 1000, y: 383, w: 1000, h:  333)))
                        expect(d.frame).to(equal(r(x: 1000, y: 50,  w: 1000, h:  333)))
                        expect(e.frame).to(equal(r(x: 1000, y: 50,  w: 1000, h:  333)))
                    }.then { () -> Promise<()> in
                        expect(dNode.kind.resize(byScreenPercentage: 0.01, inDirection: .right)) == false
                        expect(dNode.kind.resize(byScreenPercentage: 0.01, inDirection: .left)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x:   0, y: 50,  w:  980, h: 1000)))
                        expect(b.frame).to(equal(r(x: 980, y: 717, w: 1020, h:  333)))
                        expect(c.frame).to(equal(r(x: 980, y: 383, w: 1020, h:  333)))
                        expect(d.frame).to(equal(r(x: 980, y: 50,  w: 1020, h:  333)))
                        expect(e.frame).to(equal(r(x: 980, y: 50,  w: 1020, h:  333)))
                    }.then { () -> Promise<()> in
                        expect(dNode.kind.resize(byScreenPercentage: 0.01, inDirection: .up)) == true
                        return tree.awaitRefresh()
                    }.done {
                        expect(a.frame).to(equal(r(x:   0, y: 50,  w:  980, h: 1000)))
                        expect(b.frame).to(equal(r(x: 980, y: 717, w: 1020, h:  333)))
                        expect(c.frame).to(equal(r(x: 980, y: 393, w: 1020, h:  323)))
                        expect(d.frame).to(equal(r(x: 980, y: 50,  w: 1020, h:  343)))
                        expect(e.frame).to(equal(r(x: 980, y: 50,  w: 1020, h:  343)))
                    }
                }
            }

            describe("Selection") {
                var child, grandchild: ContainerNode!
                var aNode, bNode, cNode, dNode, eNode: WindowNode!
                beforeEach {
                    root.makeWindow(a.window, at: .end) { aNode = $0 }
                        .makeContainer(layout: .vertical, at: .end) { n in
                            child = n
                            n.makeWindow(b.window, at: .end) { bNode = $0 }
                             .makeWindow(c.window, at: .end) { cNode = $0 }
                             .makeContainer(layout: .horizontal, at: .end) { n in
                                 grandchild = n
                                 n.makeWindow(d.window, at: .end) { dNode = $0 }
                                  .makeWindow(e.window, at: .end) { eNode = $0 }
                             }
                        }
                }

                it("exists for every non-empty container node") {
                    expect(root.selection).toNot(beNil())
                    expect(child.selection).toNot(beNil())
                    expect(grandchild.selection).toNot(beNil())

                    let ggc = grandchild.createContainer(layout: .vertical, at: .end)
                    expect(ggc.selection).to(beNil())
                }

                it("persists locally") {
                    dNode.selectLocally()
                    expect(dNode.isSelected) == true
                    expect(eNode.isSelected) == false

                    eNode.selectLocally()
                    expect(dNode.isSelected) == false
                    expect(eNode.isSelected) == true

                    aNode.selectLocally()
                    bNode.selectLocally()

                    expect(child.isSelected) == false
                    expect(grandchild.isSelected) == false
                    expect(dNode.isSelected) == false
                    expect(eNode.isSelected) == true
                }

                it("transfers to the next node upon deletion") {
                    bNode.selectLocally()
                    expect(child.selection) == bNode.kind

                    bNode.destroy()
                    expect(child.selection) == cNode.kind
                }

                it("transfers to the previous node when there is no next node") {
                    grandchild.selectLocally()
                    expect(child.selection) == grandchild.kind

                    grandchild.destroyAll()
                    expect(child.selection) == cNode.kind
                }

                it("stays with the current node when a new node is added") {
                    eNode.selectLocally()
                    expect(eNode.isSelected) == true

                    // Before E
                    let f = createWindowForApp(fakeApp, "F")
                    grandchild.createWindow(f.window, at: .after(dNode.kind))
                    expect(eNode.isSelected) == true

                    // After E
                    let g = createWindowForApp(fakeApp, "G")
                    grandchild.createWindow(g.window, at: .after(eNode.kind))
                    expect(eNode.isSelected) == true
                }

                describe("selectGlobally") {
                    it("works") {
                        bNode.selectGlobally()
                        expect(aNode.base.isSelected) == false
                        expect(child.base.isSelected) == true
                        expect(bNode.base.isSelected) == true
                        expect(grandchild.base.isSelected) == false

                        eNode.selectGlobally()
                        expect(aNode.base.isSelected) == false
                        expect(child.base.isSelected) == true
                        expect(bNode.base.isSelected) == false
                        expect(grandchild.base.isSelected) == true
                        expect(eNode.base.isSelected) == true
                    }
                }
            }
        }
    }
}
