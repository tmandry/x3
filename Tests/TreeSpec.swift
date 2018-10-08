import Nimble
import Quick
import Swindler
@testable import x3

func r(x: Int, y: Int, w: Int, h: Int) -> CGRect {
    return CGRect(x: x, y: y, width: w, height: h)
}

class TreeSpec: QuickSpec {
    override func spec() {
        var fakeApp: FakeApplication!

        beforeEach {
            fakeApp = FakeApplication(parent: FakeState())
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
            var a, b, c: FakeWindow!

            beforeEach {
                screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 2000, height: 1060),
                                    menuBarHeight: 10,
                                    dockHeight: 50).screen
                tree = Tree(screen: screen)

                a = newWindow("A")
                b = newWindow("B")
                c = newWindow("C")
            }

            it("lays out windows horizontally by default") {
                tree.root.createWindowChild(a.window, at: .end)
                tree.root.createWindowChild(b.window, at: .end)
                tree.refresh()

                expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 1000, h: 1000)))
                expect(b.rect).toEventually(equal(r(x: 1000, y: 10, w: 1000, h: 1000)))

                tree.root.createWindowChild(c.window, at: .end)
                tree.refresh()

                expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 667, h: 1000)))
                expect(b.rect).toEventually(equal(r(x: 667,  y: 10, w: 667, h: 1000)))
                expect(c.rect).toEventually(equal(r(x: 1333, y: 10, w: 667, h: 1000)))
            }


            it("allows nesting a horizontal container inside horizontal") {
                tree.root.createWindowChild(a.window, at: .end)
                let child = tree.root.createContainerChild(layout: .horizontal, at: .end)
                child.createWindowChild(b.window, at: .end)
                child.createWindowChild(c.window, at: .end)
                tree.refresh()

                expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 1000, h: 1000)))
                expect(b.rect).toEventually(equal(r(x: 1000, y: 10, w: 500,  h: 1000)))
                expect(c.rect).toEventually(equal(r(x: 1500, y: 10, w: 500,  h: 1000)))
            }

            context("when a vertical container is nested inside a horizontal") {
                var child: ContainerNode!
                var d: FakeWindow!, dnode: WindowNode!

                beforeEach {
                    d = newWindow("D")

                    tree.root.createWindowChild(a.window, at: .end)
                    child = tree.root.createContainerChild(layout: .vertical, at: .end)
                    child.createWindowChild(b.window, at: .end)
                    child.createWindowChild(c.window, at: .end)
                    dnode = child.createWindowChild(d.window, at: .end)
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
                var d: FakeWindow!

                beforeEach {
                    d = newWindow("D")

                    tree.root.createWindowChild(a.window, at: .end)
                    child = tree.root.createContainerChild(layout: .vertical, at: .end)
                    child.createWindowChild(b.window, at: .end)
                    grandchild = child.createContainerChild(layout: .horizontal, at: .end)
                    grandchild.createWindowChild(c.window, at: .end)
                    grandchild.createWindowChild(d.window, at: .end)
                    tree.refresh()
                }

                it("sizes windows correctly") {
                    expect(a.rect).toEventually(equal(r(x: 0,    y: 10,  w: 1000, h: 1000)))
                    expect(b.rect).toEventually(equal(r(x: 1000, y: 10,  w: 1000, h: 500)))
                    expect(c.rect).toEventually(equal(r(x: 1000, y: 510, w: 500,  h: 500)))
                    expect(d.rect).toEventually(equal(r(x: 1500, y: 510, w: 500,  h: 500)))
                }

                xit("correctly resizes when a container is moved") {
                    // Note: in this case, `child` will end up having only one child window (b).
                    tree.root.addChild(child.removeChild(grandchild)!, at: .end)
                    tree.refresh()

                    expect(a.rect).toEventually(equal(r(x: 0,    y: 10,  w: 667, h: 1000)))
                    expect(b.rect).toEventually(equal(r(x: 667,  y: 10,  w: 667, h: 1000)))
                    expect(c.rect).toEventually(equal(r(x: 1333, y: 10,  w: 333, h: 1000)))
                    expect(d.rect).toEventually(equal(r(x: 1667, y: 10,  w: 333, h: 1000)))
                }
            }
        }
    }
}
