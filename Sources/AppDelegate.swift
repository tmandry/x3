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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

    var manager: WindowManager?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard AXSwift.checkIsProcessTrusted(prompt: true) else {
            print("Not trusted as an AX process; please authorize and re-launch")
            NSApp.terminate(self)
            return
        }

        let state = Swindler.state
        manager = WindowManager(state: state)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}
