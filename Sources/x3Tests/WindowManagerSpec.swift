import Cocoa
import os
import Nimble
import Quick
import Swindler
@testable import x3

private func r(x: Int, y: Int, w: Int, h: Int) -> CGRect {
    return CGRect(x: x, y: y, width: w, height: h)
}


class WindowManagerSpec: QuickSpec {
    override func spec() {
        var swindlerState: FakeState!
        var fakeApp: FakeApplication!
        var a, b, c, d, e: FakeWindow!

        func setup(screens: [FakeScreen]) {
            swindlerState = createState(screens: screens)
            fakeApp = createApp(swindlerState)
            swindlerState.frontmostApplication = fakeApp
            a = createWindowForApp(fakeApp, "A")
            b = createWindowForApp(fakeApp, "B")
            c = createWindowForApp(fakeApp, "C")
            d = createWindowForApp(fakeApp, "D")
            e = createWindowForApp(fakeApp, "E")
            _ = (a, b, c, d, e)
        }

        beforeSuite {
            SWINDLER_LOGGER = OSLog.disabled
            X3_LOGGER = Logger(OSLog.disabled)
            // X3_LOGGER = Logger(subsystem: "dev.tmandry.x3", category: "x3")
        }

        context("with a single screen") {
            var screen: FakeScreen!
            var wm: WindowManager!

            beforeEach {
                screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 2000, height: 1060),
                                    menuBarHeight: 10,
                                    dockHeight: 50)
                setup(screens: [screen])
                wm = WindowManager(state: swindlerState.state)
            }

            describe("addWindow") {
                it("lays out windows horizontally by default") {
                    wm.curSpace.addWindow(a.window)
                    wm.curSpace.addWindow(b.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))
                }

                it("raises added window") {
                    wm.curSpace.addWindow(a.window)
                    expect(fakeApp.mainWindow).toEventually(equal(a))
                    wm.curSpace.addWindow(b.window)
                    expect(fakeApp.mainWindow).toEventually(equal(b))
                }
            }

            it("moves focus around") {
                wm.curSpace.addWindow(a.window)
                wm.curSpace.addWindow(b.window)
                wm.curSpace.addWindow(c.window)

                expect(fakeApp.mainWindow).toEventually(equal(c))
                wm.curSpace.moveFocus(.left)
                expect(fakeApp.mainWindow).toEventually(equal(b))
                wm.curSpace.moveFocus(.left)
                expect(fakeApp.mainWindow).toEventually(equal(a))
                wm.curSpace.moveFocus(.left) // no-op
                wm.curSpace.moveFocus(.right)
                expect(fakeApp.mainWindow).toEventually(equal(b))
            }

            it("follows external changes to window focus") {
                print("a")
                wm.curSpace.addWindow(a.window)
                wm.curSpace.addWindow(b.window)
                wm.curSpace.addWindow(c.window)
                wm.curSpace.addWindow(d.window)

                print("b")
                expect(fakeApp.mainWindow).toEventually(equal(d))
                fakeApp.mainWindow = a
                print("c")
                expect(wm.curSpace.focusedWindow).toEventually(equal(a.window))
                wm.curSpace.moveFocus(.right)
                print("d")
                expect(fakeApp.mainWindow).toEventually(equal(b))
            }

            it("allows moving up and down the tree") {
                wm.curSpace.addWindow(a.window)
                wm.curSpace.addWindow(b.window)
                wm.curSpace.split(.vertical)
                wm.curSpace.addWindow(c.window)
                wm.curSpace.focusParent()
                wm.curSpace.moveFocusedNode(.left)
                // TODO: this next line flaked: expected to eventually equal <(1000.0, 50.0, 1000.0, 1000.0)>, got <(0.0, 50.0, 1000.0, 1000.0)>
                expect(a.frame).toEventually(equal(r(x: 1000, y:  50, w: 1000, h: 1000)))
                expect(b.frame).toEventually(equal(r(x:    0, y: 550, w: 1000, h:  500)))
                expect(c.frame).toEventually(equal(r(x:    0, y:  50, w: 1000, h:  500)))
                wm.curSpace.focusChild()
                wm.curSpace.moveFocusedNode(.right)
                expect(a.frame).toEventually(equal(r(x: 1333, y:  50, w:  667, h: 1000)))
                expect(b.frame).toEventually(equal(r(x:    0, y:  50, w:  667, h: 1000)))
                expect(c.frame).toEventually(equal(r(x:  667, y:  50, w:  667, h: 1000)))
            }

            describe("split") {
                it("with no windows, sets the direction of the root") {
                    wm.curSpace.split(.vertical)
                    wm.curSpace.addWindow(a.window)
                    wm.curSpace.addWindow(b.window)
                    expect(a.frame).toEventually(equal(r(x: 0, y: 550, w: 2000, h: 500)))
                    expect(b.frame).toEventually(equal(r(x: 0, y:  50, w: 2000, h: 500)))
                }

                it("with windows, creates a new container above the current node") {
                    wm.curSpace.addWindow(a.window)
                    let bNode = wm.curSpace.addWindowReturningNode(b.window)!
                    wm.curSpace.split(.vertical)
                    wm.curSpace.addWindow(c.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y:  50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 550, w: 1000, h:  500)))
                    expect(c.frame).toEventually(equal(r(x: 1000, y:  50, w: 1000, h:  500)))
                    expect(bNode.parent?.parent).to(equal(wm.curSpace.tree.peek().root))
                }

                it("with root selected, creates a new container above the current root") {
                    wm.curSpace.addWindow(a.window)
                    let bNode = wm.curSpace.addWindowReturningNode(b.window)!
                    wm.curSpace.focusParent()
                    wm.curSpace.split(.vertical)
                    wm.curSpace.addWindow(c.window)
                    // TODO: this line flaked (split mode): expected to eventually equal <(0.0, 550.0, 1000.0, 500.0)>, got <(0.0, 50.0, 1000.0, 1000.0)>
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 550, w: 1000, h:  500)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 550, w: 1000, h:  500)))
                    expect(c.frame).toEventually(equal(r(x: 0,    y:  50, w: 2000, h:  500)))
                    expect(bNode.parent?.parent).to(equal(wm.curSpace.tree.peek().root))
                }

                it("after repeated invocations with no windows added, only creates one container") {
                    wm.curSpace.addWindow(a.window)
                    let bNode = wm.curSpace.addWindowReturningNode(b.window)!
                    wm.curSpace.split(.vertical)
                    wm.curSpace.split(.horizontal)
                    wm.curSpace.split(.horizontal)
                    wm.curSpace.split(.vertical)
                    wm.curSpace.split(.horizontal)
                    wm.curSpace.split(.vertical)
                    wm.curSpace.addWindow(c.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y:  50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 550, w: 1000, h:  500)))
                    expect(c.frame).toEventually(equal(r(x: 1000, y:  50, w: 1000, h:  500)))
                    expect(bNode.parent?.parent).to(equal(wm.curSpace.tree.peek().root))
                }
            }

            describe("stack") {
                func testStack(to: Layout) {
                    context("when used on a horizontal layout") {
                        it("converts to a \(to) and unstacks back to horizontal") {
                            wm.curSpace.addWindow(a.window)
                            wm.curSpace.addWindow(b.window)
                            wm.curSpace.stack(layout: to)
                            expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            expect(b.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            wm.curSpace.unstack()
                            expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                            expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))
                        }
                    }

                    context("when used on a vertical layout") {
                        it("converts to a \(to) and unstacks back to vertical") {
                            wm.curSpace.split(.vertical)
                            wm.curSpace.addWindow(a.window)
                            wm.curSpace.addWindow(b.window)
                            wm.curSpace.stack(layout: to)
                            expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            expect(b.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            wm.curSpace.unstack()
                            expect(a.frame).toEventually(equal(r(x: 0, y: 550, w: 2000, h: 500)))
                            expect(b.frame).toEventually(equal(r(x: 0, y:  50, w: 2000, h: 500)))
                        }
                    }
                }

                testStack(to: .stacked)
                testStack(to: .tabbed)
            }

            context("with a single space") {
                it("recovery works") {
                    wm.curSpace.addWindow(a.window)
                    wm.curSpace.addWindow(b.window)
                    expect(fakeApp.mainWindow).toEventually(equal(b))
                    wm.curSpace.split(.vertical)
                    wm.curSpace.addWindow(c.window)

                    expect(swindlerState.state.focusedWindow).toEventually(equal(c.window))

                    let data = try! wm.serialize()
                    wm = try! WindowManager.recover(from: data, state: swindlerState.state)
                    wm.curSpace.moveFocus(.up)

                    expect(fakeApp.mainWindow).toEventually(equal(b))
                }
            }

            context("with multiple spaces") {
                var spaceA, spaceB: Int!
                beforeEach {
                    wm.curSpace.addWindow(a.window)
                    wm.curSpace.addWindow(b.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                    spaceA = swindlerState.mainScreen!.spaceId
                    spaceB = swindlerState.newSpaceId
                    swindlerState.mainScreen!.spaceId = spaceB
                    expect(wm.curSpaceId).toEventually(equal(spaceB))
                    wm.curSpace.addWindow(c.window)
                    wm.curSpace.addWindow(d.window)
                    expect(fakeApp.focusedWindow).toEventually(equal(d))
                }

                it("maintains separate layout and remembers selection per space") {
                    expect(c.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(d.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                    // Assert a/b after c/d to make sure they don't change when adding c/d.
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                    swindlerState.mainScreen!.spaceId = spaceA
                    expect(wm.curSpaceId).toEventually(equal(spaceA))
                    wm.curSpace.moveFocus(.left)
                    wm.curSpace.moveFocus(.left) // noop
                    expect(swindlerState.state.focusedWindow).toEventually(equal(a.window))

                    swindlerState.mainScreen!.spaceId = spaceB
                    expect(wm.curSpaceId).toEventually(equal(spaceB))
                    wm.curSpace.moveFocus(.left)
                    wm.curSpace.moveFocus(.left) // noop
                    expect(swindlerState.state.focusedWindow).toEventually(equal(c.window))
                }

                it("supports recovering each space's layout") {
                    let data = try! wm.serialize()
                    wm = try! WindowManager.recover(from: data, state: swindlerState.state)

                    wm.curSpace.moveFocus(.left)
                    expect(swindlerState.state.focusedWindow).toEventually(equal(c.window))

                    swindlerState.mainScreen!.spaceId = spaceA
                    expect(wm.curSpaceId).toEventually(equal(spaceA))
                    // FIXME: This is brittle :(
                    // focusedWindow must be updated after the space, so we have a way to
                    // observe that the wm saw it.
                    fakeApp.focusedWindow = b
                    expect(wm.focus).toNotEventually(beNil())

                    wm.curSpace.moveFocus(.left)
                    expect(swindlerState.state.focusedWindow).toEventually(equal(a.window))
                }
            }
        }
    }
}
