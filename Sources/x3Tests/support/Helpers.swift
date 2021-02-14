import Foundation
import Swindler
import Quick
import Nimble
import PromiseKit
@testable import x3

/// "Builder" interface for ContainerNodes.
///
/// I only foresee this being useful in tests, but that may change.
extension ContainerNode {
    @discardableResult
    func makeContainer(layout: Layout, at: InsertionPolicy = .end) -> ContainerNode {
        createContainer(layout: layout, at: at)
        return self
    }

    @discardableResult
    func makeContainer(layout: Layout,
                       at: InsertionPolicy = .end,
                       _ f: (ContainerNode) -> ())
    -> ContainerNode {
        let child = createContainer(layout: layout, at: at)
        f(child)
        return self
    }

    @discardableResult
    func makeWindow(_ window: Swindler.Window, at: InsertionPolicy = .end) -> ContainerNode {
        createWindow(window, at: at)
        return self
    }

    @discardableResult
    func makeWindow(_ window: Swindler.Window,
                    at: InsertionPolicy = .end,
                    _ f: (WindowNode) -> ())
    -> ContainerNode {
        let child = createWindow(window, at: at)
        f(child)
        return self
    }
}

func createState(screens: [FakeScreen] = [FakeScreen()]) -> FakeState {
    var state: FakeState!
    waitUntil { done in
        FakeState.initialize(screens: screens).done { s in
            state = s
            done()
        }.cauterize()
    }
    return state
}

func createApp(_ state: FakeState) -> FakeApplication {
    var app: FakeApplication!
    waitUntil { done in
        FakeApplicationBuilder(parent: state)
            .build()
            .done {
                app = $0
                done()
            }.cauterize()
    }
    return app
}

func createWindowForApp(_ app: FakeApplication, _ title: String = "FakeWindow") -> FakeWindow {
    var window: FakeWindow!
    waitUntil { done in
        app.createWindow().setTitle(title).build().done { w in
            window = w
            done()
        }.cauterize()
    }
    return window
}

func it(_ desc: String,
        timeout: TimeInterval = 1.0,
        failOnError: Bool = true,
        file: FileString = #file,
        line: UInt = #line,
        closure: @escaping () -> Promise<()>) {
    it(desc, file: file.description, line: line, closure: {
        let promise = closure()
        waitUntil(timeout: timeout, file: file, line: line) { done in
            promise.done { _ in
                done()
            }.catch { error in
                if failOnError {
                    fail("Promise failed with error \(error)", file: file, line: line)
                }
                done()
            }
        }
    } as () -> Void)
}
