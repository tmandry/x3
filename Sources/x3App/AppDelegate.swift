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

let RECOVER = "--recover"
let OK_LINE = "recover ok"

func recover(_ state: Swindler.State) throws -> WindowManager {
    print("recover: reading")
    let data = FileHandle.standardInput.readDataToEndOfFile()
    print("recover: got data: \(data)")
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
                print("Reloading with payload:")
                print(String(decoding: data, as: UTF8.self))

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
                    print("Launching: \(task)")
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
                print("output: \(outputData)")
                guard let outputData = outputData else {
                    print("Reloading not successful: stdout not available. Resuming.")
                    print("stderr:")
                    task.terminate()
                    if let stderr = try errorPipe.fileHandleForReading.readToEnd() {
                        print(String(decoding: stderr, as: UTF8.self))
                    } else {
                        print("(not available)")
                    }
                    return
                }
                let output = String(decoding: outputData, as: UTF8.self)

                if !output.components(separatedBy: "\n").contains(OK_LINE) {
                    print("Reloading not successful: could not find the line `\(OK_LINE)`. Resuming.")
                    print("Output:")
                    print(output)
                    print("Error:")
                    print(String(decoding: errorPipe.fileHandleForReading.availableData, as: UTF8.self))
                    task.terminate()
                    return
                }
                if !task.isRunning {
                    print("Reloading not successful: Got `\(OK_LINE)` but process has exited with code " +
                        "\(task.terminationStatus). Resuming.")
                    return
                }

                print("Reload successful. Terminating.")
                exit(0)
            } catch {
                print("Reloading not successful: error: \(error). Resuming.")
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
            print("Not trusted as an AX process; please authorize and re-launch")
            NSApp.terminate(self)
            return
        }

        hotkeys = HotKeyManager()

        Swindler.initialize().done { state in
            print("done with init. args: \(CommandLine.arguments)")
            if CommandLine.arguments.contains(RECOVER) {
                self.manager = try recover(state)
            } else {
                self.manager = WindowManager(state: state)
            }
            self.manager.reload = reload
            self.manager.registerHotKeys(self.hotkeys)
        }.catch { error in
            fatalError("Swindler failed to initialize: \(error)")
        }
    }

    public func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}
