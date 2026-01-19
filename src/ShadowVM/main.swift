//
//  main.swift
//  ShadowVM
//
//  Created by Saagar Jha on 11/20/21.
//

import AppKit
import Darwin
import Foundation
import ShadowVMCore

ShadowVMConfig.configure(
  homeDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    ".shadowvm-ce", isDirectory: true)
)

ShadowVMCELogging.configure()

setbuf(stdout, nil)
setbuf(stderr, nil)

let args = ShadowVMCECLI.userArguments()
if !args.isEmpty {
  do {
    if let command = try ShadowVMCECLI.parse(args) {
    if let request = ShadowVMCECLI.launchRequest(for: command),
      shouldForwardCLIRequestToRunningApp()
    {
      ShadowVMCECLI.sendCLIRequest(request)
      activateRunningApp()
      ShadowVMCECLI.exit(0)
    }
      let exitCode = ShadowVMCECLI.runBlocking(command)
      if exitCode != 0 {
        ShadowVMCECLI.exit(exitCode)
      }
      if let request = ShadowVMCECLI.launchRequest(for: command) {
        if shouldOpenUIForCLIRequest() {
          ShadowVMCECLI.setLaunchRequest(request)
        } else {
          ShadowVMCECLI.exit(exitCode)
        }
      } else {
        ShadowVMCECLI.exit(exitCode)
      }
    }
  } catch {
    ShadowVMCECLI.printError(error)
    ShadowVMCECLI.exit(2)
  }
}

let delegate = unsafelyRunOnMainActor {
  AppDelegate()
}
NSApplication.shared.delegate = delegate
NSApp.run()

private func shouldForwardCLIRequestToRunningApp() -> Bool {
  guard let bundleID = Bundle.main.bundleIdentifier else {
    return false
  }
  let currentPID = ProcessInfo.processInfo.processIdentifier
  let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != currentPID }
  return !others.isEmpty
}

private func shouldOpenUIForCLIRequest() -> Bool {
  guard let bundleID = Bundle.main.bundleIdentifier else {
    return true
  }
  let currentPID = ProcessInfo.processInfo.processIdentifier
  let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != currentPID }
  return others.isEmpty
}

private func activateRunningApp() {
  guard let bundleID = Bundle.main.bundleIdentifier else {
    return
  }
  let currentPID = ProcessInfo.processInfo.processIdentifier
  let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != currentPID }
  for app in others {
    _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
  }
}
