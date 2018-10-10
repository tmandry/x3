import Nimble
import Quick
import Swindler
@testable import x3

func r(x: Int, y: Int, w: Int, h: Int) -> CGRect {
    return CGRect(x: x, y: y, width: w, height: h)
}

/// "Builder" interface for ContainerNodes.
///
/// I only foresee this being useful in tests, but that may change.
extension ContainerNode {
    @discardableResult
    func makeContainer(layout: Layout, at: InsertionPolicy) -> ContainerNode {
        createContainer(layout: layout, at: at)
        return self
    }

    @discardableResult
    func makeContainer(layout: Layout, at: InsertionPolicy, _ f: (ContainerNode) -> ()) -> ContainerNode {
        let child = createContainer(layout: layout, at: at)
        f(child)
        return self
    }

    @discardableResult
    func makeWindow(_ window: Swindler.Window, at: InsertionPolicy) -> ContainerNode {
        createWindow(window, at: at)
        return self
    }

    @discardableResult
    func makeWindow(_ window: Swindler.Window, at: InsertionPolicy, _ f: (WindowNode) -> ()) -> ContainerNode {
        let child = createWindow(window, at: at)
        f(child)
        return self
    }
}

class TreeSpec: QuickSpec {
    override func spec() {
        var fakeApp: FakeApplication!
        var a, b, c, d, e: FakeWindow!

        beforeEach {
            fakeApp = FakeApplication(parent: FakeState())
            a = newWindow("A")
            b = newWindow("B")
            c = newWindow("C")
            d = newWindow("D")
            e = newWindow("E")
        }

        func newWindow(_ title: String = "FakeWindow") -> FakeWindow {
            var window: FakeWindow!
            waitUntil { done in
                fakeApp.createWindow().setTitle(title).build().then { w -> () in
                    window = w
                    done()
                }.always {}
            }
            return window
        }

        context("with a single screen") {
            var screen: Screen!
            var tree: Tree!

            var root: ContainerNode {
                get {
                    return tree.root
                }
            }

            beforeEach {
                screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 2000, height: 1060),
                                    menuBarHeight: 10,
                                    dockHeight: 50).screen
                tree = Tree(screen: screen)

            }

            it("lays out windows horizontally by default") {
                tree.root.createWindow(a.window, at: .end)
                tree.root.createWindow(b.window, at: .end)
                tree.refresh()

                expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 1000, h: 1000)))
                expect(b.rect).toEventually(equal(r(x: 1000, y: 10, w: 1000, h: 1000)))

                tree.root.createWindow(c.window, at: .end)
                tree.refresh()

                expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 667, h: 1000)))
                expect(b.rect).toEventually(equal(r(x: 667,  y: 10, w: 667, h: 1000)))
                expect(c.rect).toEventually(equal(r(x: 1333, y: 10, w: 667, h: 1000)))
            }

            it("removes windows when they are destroyed") {
                let anode = tree.root.createWindow(a.window, at: .end)
                let bnode = tree.root.createWindow(b.window, at: .end)
                let cnode = tree.root.createWindow(c.window, at: .end)
                tree.refresh()

                bnode.destroy()
                tree.refresh()

                expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 1000, h: 1000)))
                expect(c.rect).toEventually(equal(r(x: 1000, y: 10, w: 1000, h: 1000)))

                anode.destroy()
                tree.refresh()

                expect(c.rect).toEventually(equal(r(x: 0, y: 10, w: 2000, h: 1000)))

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

                expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 1000, h: 1000)))
                expect(b.rect).toEventually(equal(r(x: 1000, y: 10, w: 500,  h: 1000)))
                expect(c.rect).toEventually(equal(r(x: 1500, y: 10, w: 500,  h: 1000)))
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
                    expect(a.rect).toEventually(equal(r(x: 0,    y: 10,  w: 1000, h: 1000)))
                    expect(b.rect).toEventually(equal(r(x: 1000, y: 10,  w: 1000, h: 333)))
                    expect(c.rect).toEventually(equal(r(x: 1000, y: 343, w: 1000, h: 333)))
                    expect(d.rect).toEventually(equal(r(x: 1000, y: 677, w: 1000, h: 333)))
                }

                it("correctly resizes when windows are moved") {
                    tree.root.addChild(child.removeChild(dnode)!, at: .end)
                    tree.refresh()

                    expect(a.rect).toEventually(equal(r(x: 0,    y: 10,  w: 667, h: 1000)))
                    expect(b.rect).toEventually(equal(r(x: 667,  y: 10,  w: 667, h: 500)))
                    expect(c.rect).toEventually(equal(r(x: 667,  y: 510, w: 667, h: 500)))
                    expect(d.rect).toEventually(equal(r(x: 1333, y: 10,  w: 667, h: 1000)))
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
                    expect(a.rect).toEventually(equal(r(x: 0,    y: 10,  w: 1000, h: 1000)))
                    expect(b.rect).toEventually(equal(r(x: 1000, y: 10,  w: 1000, h: 500)))
                    expect(c.rect).toEventually(equal(r(x: 1000, y: 510, w: 500,  h: 500)))
                    expect(d.rect).toEventually(equal(r(x: 1500, y: 510, w: 500,  h: 500)))
                }

                it("correctly resizes when a container is moved") {
                    // Note: in this case, `child` will end up having only one child window (b).
                    tree.root.addChild(child.removeChild(grandchild)!, at: .end)
                    tree.refresh()

                    expect(a.rect).toEventually(equal(r(x: 0,    y: 10,  w: 667, h: 1000)))
                    expect(b.rect).toEventually(equal(r(x: 667,  y: 10,  w: 667, h: 1000)))
                    expect(c.rect).toEventually(equal(r(x: 1333, y: 10,  w: 334, h: 1000)))
                    expect(d.rect).toEventually(equal(r(x: 1667, y: 10,  w: 334, h: 1000)))
                }
            }

            describe("Crawler") {
                func checkMove(_ direction: Direction, from: FakeWindow, to: FakeWindow,
                               file: String = #file, line: UInt = #line) {
                    var crawler = Crawler(at: root.find(window: from.window)!)
                    crawler.move(direction)
                    expect(crawler.peek(), file: file, line: line).to(equal(
                        root.find(window: to.window)!.kind
                    ))
                }

                beforeEach {
                    root.makeWindow(a.window, at: .end)
                        .makeContainer(layout: .vertical, at: .end) { n in
                            n.makeWindow(b.window, at: .end)
                             .makeWindow(c.window, at: .end)
                             .makeContainer(layout: .horizontal, at: .end) { n in
                                 n.makeWindow(d.window, at: .end)
                                  .makeWindow(e.window, at: .end)
                             }
                        }
                }

                it("moves predictably") {
                    checkMove(.right, from: d, to: e)
                    checkMove(.up,    from: d, to: c)
                    checkMove(.left,  from: d, to: a)
                }
            }
        }
    }
}
