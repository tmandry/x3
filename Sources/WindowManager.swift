import Carbon
import Swindler

class WindowManager {
    var state: Swindler.State
    var tree: Tree
    let hotKeys: HotKeyManager

    init(state: Swindler.State) {
        self.state = state
        self.tree = Tree()

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
                if !self.tree.root.contains(window: window) {
                    self.tree.root.createWindowChild(window, at: .end)
                }
                debugPrint(String(describing: self.tree))
            }
        }
    }
}
