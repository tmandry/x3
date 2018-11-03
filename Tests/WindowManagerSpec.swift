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
            fakeApp = FakeApplication(parent: swindlerState)
            swindlerState.frontmostApplication = fakeApp
            a = createWindowForApp(fakeApp, "A")
            b = createWindowForApp(fakeApp, "B")
            c = createWindowForApp(fakeApp, "C")
            d = createWindowForApp(fakeApp, "D")
            e = createWindowForApp(fakeApp, "E")
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
                    expect(a.rect).toEventually(equal(r(x: 0,    y: 10, w: 1000, h: 1000)))
                    expect(b.rect).toEventually(equal(r(x: 1000, y: 10, w: 1000, h: 1000)))
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
        }
    }
}
