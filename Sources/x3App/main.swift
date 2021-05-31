import Cocoa
import Logging
import x3

LoggingSystem.bootstrap(StreamLogHandler.standardError)
var log = Logger(label: "dev.tmandry.x3")
log.logLevel = .debug
X3_LOGGER = log

let applicationDelegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
application.delegate = applicationDelegate
application.run()
