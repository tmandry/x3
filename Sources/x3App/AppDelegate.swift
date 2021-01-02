//
//  AppDelegate.swift
//  x3
//
//  Created by Tyler Mandry on 10/21/17.
//  Copyright © 2017 Tyler Mandry. All rights reserved.
//

import Cocoa
import AXSwift
import Swindler
import x3

public class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

    var manager: WindowManager!
    var hotkeys: HotKeyManager!

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        // TODO: re-enable prompt; disabled because it gets in the way during testing.
        guard AXSwift.checkIsProcessTrusted(prompt: true) else {
            print("Not trusted as an AX process; please authorize and re-launch")
            NSApp.terminate(self)
            return
        }

        hotkeys = HotKeyManager()

        Swindler.initialize().done { state in
            self.manager = WindowManager(state: state)
            self.manager.registerHotKeys(self.hotkeys)
        }.catch { error in
            fatalError("Swindler failed to initialize: \(error)")
        }
    }

    public func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}
