import Nimble
import Quick
import Swindler
@testable import x3

class TreeSpec: QuickSpec {
    override func spec() {
        var screen: Screen!
        var fakeApp: FakeApplication!

        beforeEach {
            screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                menuBarHeight: 10,
                                dockHeight: 50).screen
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

        it("lays out two windows side-by-side") {
            let a = newWindow("A")
            let b = newWindow("B")

            let tree = Tree(screen: screen)
            tree.root.createWindowChild(a.window, at: .end)
            tree.root.createWindowChild(b.window, at: .end)
            tree.refresh()

            expect(a.rect).toEventually(equal(CGRect(x: 0,   y: 10, width: 960, height: 1020)))
            expect(b.rect).toEventually(equal(CGRect(x: 960, y: 10, width: 960, height: 1020)))
        }
    }
}
