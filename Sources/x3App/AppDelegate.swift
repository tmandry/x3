//
//  AppDelegate.swift
//  x3
//
//  Copyright © 2017 Tyler Mandry. All rights reserved.
//

import Cocoa
import AXSwift
import PromiseKit
import Swindler
import x3

let RECOVER = "--recover"
let OK_LINE = "recover ok"

func recover() throws -> Promise<WindowManager> {
    log.info("recover: reading")
    let data = FileHandle.standardInput.readDataToEndOfFile()
    log.info("recover: got data: \(data)")
    let manager = try WindowManager.recover(from: data)

    // Signal restoration complete, then close stdout and redirect future output
    // to stderr.
    print(OK_LINE)
    fflush(stdout)
    FileHandle.standardOutput.closeFile()
    dup2(fileno(stderr), STDOUT_FILENO)
    return manager
}

func reload(_ wm: WindowManager) {
    if #available(macOS 10.15.4, *) {
        let thread = Thread {
            do {
                let data = try wm.serialize()
                log.info("Reloading")
                log.debug("payload: \(String(decoding: data, as: UTF8.self))")

                let program = CommandLine.arguments[0]
                let task = Process()
                task.arguments = [RECOVER]
                let dataPipe = Pipe()
                let statusPipe = Pipe()
                let errorPipe = Pipe()
                task.standardInput = dataPipe
                task.standardOutput = statusPipe
                task.standardError = errorPipe
                if #available(macOS 10.13, *) {
                    task.executableURL = URL(fileURLWithPath: program)
                    try task.run()
                } else {
                    task.launchPath = program
                    task.launch()
                }

                dataPipe.fileHandleForWriting.write(data)
                try dataPipe.fileHandleForWriting.close()

                var outData: Data?
                try DispatchQueue.global().sync {
                    outData = try statusPipe.fileHandleForReading.readToEnd()
                }
                guard let outputData = outData else {
                    log.error("Reloading not successful: stdout not available. Resuming.")
                    log.debug("stderr:")
                    task.terminate()
                    if let stderr = try errorPipe.fileHandleForReading.readToEnd() {
                        log.debug("\(String(decoding: stderr, as: UTF8.self))")
                    } else {
                        log.debug("(not available)")
                    }
                    return
                }
                let output = String(decoding: outputData, as: UTF8.self)

                if !output.components(separatedBy: "\n").contains(OK_LINE) {
                    log.error("Reloading not successful: could not find the line `\(OK_LINE)`. Resuming.")
                    log.debug("Output:")
                    log.debug("\(output)")
                    log.debug("Error:")
                    log.debug("""
                        \(String(decoding: errorPipe.fileHandleForReading.availableData, as: UTF8.self))
                    """)
                    task.terminate()
                    return
                }
                Thread.sleep(forTimeInterval: 0.5)
                if !task.isRunning {
                    log.error("""
                        Reloading not successful: Got `\(OK_LINE)` but process has exited with code \
                        \(task.terminationStatus). Resuming.
                    """)
                    log.debug("Output:")
                    log.debug("\(output)")
                    log.debug("Error:")
                    log.debug("""
                        \(String(decoding: errorPipe.fileHandleForReading.availableData, as: UTF8.self))
                    """)
                    return
                }

                log.info("Reload successful. Terminating.")

                // Doing this on the main thread is a tiny bit cleaner.
                DispatchQueue.main.sync {
                    exit(0)
                }
            } catch {
                log.error("""
                    Reloading not successful: error: \
                    \(String(describing: error), privacy: .public). Resuming.
                """)
            }
        }
        thread.start()
    }
}

public class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

    var manager: WindowManager!
    var hotkeys: HotKeyManager!

    public func application(_ app: NSApplication, willEncodeRestorableState coder: NSCoder) {
        log.info("willEncodeRestorableState ")
    }

    public func application(_ app: NSApplication, didDecodeRestorableState coder: NSCoder) {
        log.info("didDecodeRestorableState ")
    }

    //public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    //    true
    //}

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        log.info("applicationDidFinishLaunching")
        guard AXSwift.checkIsProcessTrusted(prompt: true) else {
            log.error("Not trusted as an AX process; please authorize and re-launch")
            "Not trusted as an AX process; please authorize and re-launch"
                .data(using: .utf8)
                .map(FileHandle.standardError.write)
            NSApp.terminate(self)
            return
        }

        UserDefaults.standard.register(defaults: ["NSWindowRestoresWorkspaceAtLaunch": true])

        hotkeys = HotKeyManager()

        log.debug("args: \(CommandLine.arguments)")

        PromiseKit.firstly { () -> Promise<WindowManager> in
            if CommandLine.arguments.contains(RECOVER) {
                return try recover()
            } else {
                return WindowManager.initialize()
            }
        }.done { wm in
            log.debug("done with init")
            self.manager = wm
            self.manager.reload = reload
            self.manager.registerHotKeys(self.hotkeys)
        }.catch { error in
            log.critical("""
                Failed to initialize: \(String(describing: error), privacy: .public)
            """)
            fatalError("Failed to initialize: \(error)")
        }
    }

    public func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        log.info("applicationWillTerminate")
    }
}
