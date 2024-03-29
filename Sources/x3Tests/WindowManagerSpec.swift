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
                    wm.addWindow(a.window)
                    wm.addWindow(b.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))
                }

                it("raises added window") {
                    wm.addWindow(a.window)
                    expect(fakeApp.mainWindow).toEventually(equal(a))
                    wm.addWindow(b.window)
                    expect(fakeApp.mainWindow).toEventually(equal(b))
                }
            }

            it("moves focus around") {
                wm.addWindow(a.window)
                wm.addWindow(b.window)
                wm.addWindow(c.window)

                expect(fakeApp.mainWindow).toEventually(equal(c))
                wm.moveFocus(.left)
                expect(fakeApp.mainWindow).toEventually(equal(b))
                wm.moveFocus(.left)
                expect(fakeApp.mainWindow).toEventually(equal(a))
                wm.moveFocus(.left) // no-op
                wm.moveFocus(.right)
                expect(fakeApp.mainWindow).toEventually(equal(b))
            }

            it("follows external changes to window focus") {
                wm.addWindow(a.window)
                wm.addWindow(b.window)
                wm.addWindow(c.window)
                wm.addWindow(d.window)

                expect(fakeApp.mainWindow).toEventually(equal(d))
                fakeApp.mainWindow = a
                expect(wm.focusedWindow).toEventually(equal(a.window))
                wm.moveFocus(.right)
                expect(fakeApp.mainWindow).toEventually(equal(b))
            }

            it("allows moving up and down the tree") {
                wm.addWindow(a.window)
                wm.addWindow(b.window)
                wm.split(.vertical)
                wm.addWindow(c.window)
                wm.focusParent()
                wm.moveFocusedNode(.left)
                // TODO: this next line flaked: expected to eventually equal <(1000.0, 50.0, 1000.0, 1000.0)>, got <(0.0, 50.0, 1000.0, 1000.0)>
                expect(a.frame).toEventually(equal(r(x: 1000, y:  50, w: 1000, h: 1000)))
                expect(b.frame).toEventually(equal(r(x:    0, y: 550, w: 1000, h:  500)))
                expect(c.frame).toEventually(equal(r(x:    0, y:  50, w: 1000, h:  500)))
                wm.focusChild()
                wm.moveFocusedNode(.right)
                expect(a.frame).toEventually(equal(r(x: 1333, y:  50, w:  667, h: 1000)))
                expect(b.frame).toEventually(equal(r(x:    0, y:  50, w:  667, h: 1000)))
                expect(c.frame).toEventually(equal(r(x:  667, y:  50, w:  667, h: 1000)))
            }

            describe("split") {
                it("with no windows, sets the direction of the root") {
                    wm.split(.vertical)
                    wm.addWindow(a.window)
                    wm.addWindow(b.window)
                    expect(a.frame).toEventually(equal(r(x: 0, y: 550, w: 2000, h: 500)))
                    expect(b.frame).toEventually(equal(r(x: 0, y:  50, w: 2000, h: 500)))
                }

                it("with windows, creates a new container above the current node") {
                    wm.addWindow(a.window)
                    let bNode = wm.addWindowReturningNode(b.window)!
                    wm.split(.vertical)
                    wm.addWindow(c.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y:  50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 550, w: 1000, h:  500)))
                    expect(c.frame).toEventually(equal(r(x: 1000, y:  50, w: 1000, h:  500)))
                    expect(bNode.parent?.parent).to(equal(wm.tree.peek().root))
                }

                it("with root selected, creates a new container above the current root") {
                    wm.addWindow(a.window)
                    let bNode = wm.addWindowReturningNode(b.window)!
                    wm.focusParent()
                    wm.split(.vertical)
                    wm.addWindow(c.window)
                    // TODO: this line flaked (split mode): expected to eventually equal <(0.0, 550.0, 1000.0, 500.0)>, got <(0.0, 50.0, 1000.0, 1000.0)>
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 550, w: 1000, h:  500)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 550, w: 1000, h:  500)))
                    expect(c.frame).toEventually(equal(r(x: 0,    y:  50, w: 2000, h:  500)))
                    expect(bNode.parent?.parent).to(equal(wm.tree.peek().root))
                }

                it("after repeated invocations with no windows added, only creates one container") {
                    wm.addWindow(a.window)
                    let bNode = wm.addWindowReturningNode(b.window)!
                    wm.split(.vertical)
                    wm.split(.horizontal)
                    wm.split(.horizontal)
                    wm.split(.vertical)
                    wm.split(.horizontal)
                    wm.split(.vertical)
                    wm.addWindow(c.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y:  50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 550, w: 1000, h:  500)))
                    expect(c.frame).toEventually(equal(r(x: 1000, y:  50, w: 1000, h:  500)))
                    expect(bNode.parent?.parent).to(equal(wm.tree.peek().root))
                }
            }

            describe("stack") {
                func testStack(to: Layout) {
                    context("when used on a horizontal layout") {
                        it("converts to a \(to) and unstacks back to horizontal") {
                            wm.addWindow(a.window)
                            wm.addWindow(b.window)
                            wm.stack(layout: to)
                            expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            expect(b.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            wm.unstack()
                            expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                            expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))
                        }
                    }

                    context("when used on a vertical layout") {
                        it("converts to a \(to) and unstacks back to vertical") {
                            wm.split(.vertical)
                            wm.addWindow(a.window)
                            wm.addWindow(b.window)
                            wm.stack(layout: to)
                            expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            expect(b.frame).toEventually(equal(r(x: 0,    y: 50, w: 2000, h: 1000)))
                            wm.unstack()
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
                    wm.addWindow(a.window)
                    wm.addWindow(b.window)
                    expect(fakeApp.mainWindow).toEventually(equal(b))
                    wm.split(.vertical)
                    wm.addWindow(c.window)

                    expect(swindlerState.state.focusedWindow).toEventually(equal(c.window))

                    let data = try! wm.serialize()
                    wm = try! WindowManager.recover(from: data, state: swindlerState.state)
                    wm.moveFocus(.up)

                    expect(fakeApp.mainWindow).toEventually(equal(b))
                }
            }

            context("with multiple spaces") {
                var spaceA, spaceB: Int!
                beforeEach {
                    wm.addWindow(a.window)
                    wm.addWindow(b.window)
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                    spaceA = swindlerState.mainScreen!.spaceId
                    spaceB = swindlerState.newSpaceId
                    swindlerState.mainScreen!.spaceId = spaceB
                    expect(wm.curSpace).toEventually(equal(spaceB))
                    wm.addWindow(c.window)
                    wm.addWindow(d.window)
                    expect(fakeApp.focusedWindow).toEventually(equal(d))
                }

                it("maintains separate layout and remembers selection per space") {
                    expect(c.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(d.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                    // Assert a/b after c/d to make sure they don't change when adding c/d.
                    expect(a.frame).toEventually(equal(r(x: 0,    y: 50, w: 1000, h: 1000)))
                    expect(b.frame).toEventually(equal(r(x: 1000, y: 50, w: 1000, h: 1000)))

                    swindlerState.mainScreen!.spaceId = spaceA
                    expect(wm.curSpace).toEventually(equal(spaceA))
                    wm.moveFocus(.left)
                    wm.moveFocus(.left) // noop
                    expect(swindlerState.state.focusedWindow).toEventually(equal(a.window))

                    swindlerState.mainScreen!.spaceId = spaceB
                    expect(wm.curSpace).toEventually(equal(spaceB))
                    wm.moveFocus(.left)
                    wm.moveFocus(.left) // noop
                    expect(swindlerState.state.focusedWindow).toEventually(equal(c.window))
                }

                it("supports recovering each space's layout") {
                    let data = try! wm.serialize()
                    wm = try! WindowManager.recover(from: data, state: swindlerState.state)

                    wm.moveFocus(.left)
                    expect(swindlerState.state.focusedWindow).toEventually(equal(c.window))

                    swindlerState.mainScreen!.spaceId = spaceA
                    expect(wm.curSpace).toEventually(equal(spaceA))
                    // FIXME: This is brittle :(
                    // focusedWindow must be updated after the space, so we have a way to
                    // observe that the wm saw it.
                    fakeApp.focusedWindow = b
                    expect(wm.focus).toNotEventually(beNil())

                    wm.moveFocus(.left)
                    expect(swindlerState.state.focusedWindow).toEventually(equal(a.window))
                }
            }
        }
    }
}
