import Cocoa
import os
import x3
import Swindler

let subsystem = "dev.tmandry.x3"
var log = Logger(subsystem: subsystem, category: "x3")
X3_LOGGER = log
SWINDLER_LOGGER = OSLog(subsystem: subsystem, category: "swindler")

DispatchQueue.main.async {
    log.info("main.swift dispatch")
}

let applicationDelegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
application.delegate = applicationDelegate

signal(SIGINT) { _ in
    application.terminate(nil)
}

application.run()
