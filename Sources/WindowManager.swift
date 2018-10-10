import Carbon
import Swindler

struct TreeWrapper {
    private var tree: Tree

    init(_ tree: Tree) {
        self.tree = tree
    }
}
extension TreeWrapper {
    /// Use this when modifying the tree. It always ensures refresh is called.
    func with(_ f: (Tree) -> Void) -> Void {
        f(self.tree)
        self.tree.refresh()
    }

    /// Use this when only inspecting the tree. You must not modify the tree using the return value
    /// of this function!
    func peek() -> Tree {
        return self.tree
    }
}

class WindowManager {
    var state: Swindler.State
    var tree: TreeWrapper
    let hotKeys: HotKeyManager

    init(state: Swindler.State) {
        self.state = state
        self.tree = TreeWrapper(Tree(screen: state.screens.last!))

        //NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        //    debugPrint("Got event: \(event)")
        //}

        hotKeys = HotKeyManager()
        hotKeys.register(keyCode: kVK_ANSI_L, modifierKeys: optionKey) {
            debugPrint("woohoo!")
        }
        hotKeys.register(keyCode: kVK_ANSI_H, modifierKeys: optionKey) {
            debugPrint("wahhah!")
        }
        hotKeys.register(keyCode: kVK_ANSI_X, modifierKeys: optionKey) {
            debugPrint(String(describing:
                self.state.frontmostApplication.value?.mainWindow.value?.title.value))
            if let window = self.state.frontmostApplication.value?.mainWindow.value {
                self.tree.with { tree in
                    if !tree.root.contains(window: window) {
                        tree.root.createWindow(window, at: .end)
                    }
                }
                debugPrint(String(describing: self.tree.peek()))
            }
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifierKeys: optionKey) {
            self.tree.peek().refresh()
        }

        state.on { (event: WindowDestroyedEvent) in
            self.tree.with { tree in
                if let node = tree.find(window: event.window) {
                    node.destroy()
                }
            }
        }
    }
}
