import Swindler
import Nimble
@testable import x3

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
    func makeContainer(layout: Layout,
                       at: InsertionPolicy,
                       _ f: (ContainerNode) -> ())
    -> ContainerNode {
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
    func makeWindow(_ window: Swindler.Window,
                    at: InsertionPolicy,
                    _ f: (WindowNode) -> ())
    -> ContainerNode {
        let child = createWindow(window, at: at)
        f(child)
        return self
    }
}

func createWindowForApp(_ app: FakeApplication, _ title: String = "FakeWindow") -> FakeWindow {
    var window: FakeWindow!
    waitUntil { done in
        app.createWindow().setTitle(title).build().then { w -> () in
            window = w
            done()
        }.always {}
    }
    return window
}
