import Cocoa
import Nimble
import Quick
import Swindler
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

            it("lays out windows horizontally by default") {
                tree.root.createWindow(a.window, at: .end)
                tree.root.createWindow(b.window, at: .end)
                tree.refresh()

                expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                tree.root.createWindow(c.window, at: .end)
                tree.refresh()

                expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 667, h: 1000)))
                expect(b.frame).toEventually(equal(r(x: 667,  y: 50, w: 667, h: 1000)))
                expect(c.frame).toEventually(equal(r(x: 1333, y: 50, w: 667, h: 1000)))
            }

            it("removes windows when they are destroyed") {
                let anode = tree.root.createWindow(a.window, at: .end)
                let bnode = tree.root.createWindow(b.window, at: .end)
                let cnode = tree.root.createWindow(c.window, at: .end)
                tree.refresh()

                bnode.destroy()
                tree.refresh()

                expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                expect(c.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                anode.destroy()
                tree.refresh()

                expect(c.frame).toEventually(equal(r(x: 0, y: 50, w: 2000, h: 1000)))

                // Test that we don't crash upon destroying the last window.
                cnode.destroy()
                tree.refresh()
            }

            it("allows nesting a horizontal container inside horizontal") {
                tree.root.createWindow(a.window, at: .end)
                let child = tree.root.createContainer(layout: .horizontal, at: .end)
                child.createWindow(b.window, at: .end)
                child.createWindow(c.window, at: .end)
                tree.refresh()

                expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 500,  h: 1000)))
                expect(c.frame).toEventually(equal(r(x: 1500, y: 50, w: 500,  h: 1000)))
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
                    tree.refresh()
                }

                it("sizes windows correctly") {
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 717, w: 1000, h: 333)))
                    expect(c.frame).toEventually(equal(r(x: 1000, y: 383, w: 1000, h: 333)))
                    expect(d.frame).toEventually(equal(r(x: 1000, y: 50,  w: 1000, h: 333)))
                }

                it("correctly resizes when windows are moved") {
                    tree.root.addChild(child.removeChild(dnode)!, at: .end)
                    tree.refresh()

                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50,  w: 667, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 667,  y: 550, w: 667, h: 500)))
                    expect(c.frame).toEventually(equal(r(x: 667,  y: 50,  w: 667, h: 500)))
                    expect(d.frame).toEventually(equal(r(x: 1333, y: 50,  w: 667, h: 1000)))
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
                    tree.refresh()
                }

                it("sizes windows correctly") {
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50,  w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 550, w: 1000, h: 500)))
                    expect(c.frame).toEventually(equal(r(x: 1000, y: 50,  w: 500,  h: 500)))
                    expect(d.frame).toEventually(equal(r(x: 1500, y: 50,  w: 500,  h: 500)))
                }

                it("correctly resizes when a container is moved") {
                    // Note: in this case, `child` will end up having only one child window (b).
                    tree.root.addChild(child.removeChild(grandchild)!, at: .end)
                    tree.refresh()

                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50,  w: 667, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 667,  y: 50,  w: 667, h: 1000)))
                    expect(c.frame).toEventually(equal(r(x: 1333, y: 50,  w: 334, h: 1000)))
                    expect(d.frame).toEventually(equal(r(x: 1667, y: 50,  w: 334, h: 1000)))
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
