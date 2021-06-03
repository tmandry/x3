//
//  AppDelegate.swift
//  x3
//
//  Copyright © 2017 Tyler Mandry. All rights reserved.
//

import Cocoa
import AXSwift
import Swindler
import x3

let RECOVER = "--recover"
let OK_LINE = "recover ok"

func recover(_ state: Swindler.State) throws -> WindowManager {
    log.info("recover: reading")
    let data = FileHandle.standardInput.readDataToEndOfFile()
    log.info("recover: got data: \(data)")
    let manager = try WindowManager.recover(from: data, state: state)
    print(OK_LINE)
    fflush(stdout)
    FileHandle.standardOutput.closeFile()
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

                var outputData: Data?
                try DispatchQueue.global().sync {
                    outputData = try statusPipe.fileHandleForReading.readToEnd()
                }
                guard let outputData = outputData else {
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
                if !task.isRunning {
                    log.error("""
                        Reloading not successful: Got `\(OK_LINE)` but process has exited with code \
                        \(task.terminationStatus). Resuming.
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

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard AXSwift.checkIsProcessTrusted(prompt: true) else {
            log.error("Not trusted as an AX process; please authorize and re-launch")
            print("Not trusted as an AX process; please authorize and re-launch")
            NSApp.terminate(self)
            return
        }

        hotkeys = HotKeyManager()

        Swindler.initialize().done { state in
            log.debug("done with init. args: \(CommandLine.arguments)")
            if CommandLine.arguments.contains(RECOVER) {
                self.manager = try recover(state)
            } else {
                self.manager = WindowManager(state: state)
            }
            self.manager.reload = reload
            self.manager.registerHotKeys(self.hotkeys)
        }.catch { error in
            log.critical("""
                Swindler failed to initialize: \(String(describing: error), privacy: .public)
            """)
            fatalError("Swindler failed to initialize: \(error)")
        }
    }

    public func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}
