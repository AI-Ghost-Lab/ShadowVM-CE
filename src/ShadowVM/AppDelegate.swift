//
//  AppDelegate.swift
//  ShadowVM
//
//  Created by Saagar Jha on 11/20/21.
//

import Cocoa
import ShadowVMCore
import UniformTypeIdentifiers

extension UTType {
  static let vmApple = Self(exportedAs: "com.shadowvm.vmapple")
  static let vmAppleLegacy = Self(importedAs: "com.saagarjha.vmapple")
  static let vmAppleLegacyCE = Self(importedAs: "com.gaoxiaodiao.shadowVM-CE")
  static let vmAppleAll: [UTType] = [vmApple, vmAppleLegacy, vmAppleLegacyCE]
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  private var didPresentInitialOpenPanel = false
  private var initialOpenPanelWorkItem: DispatchWorkItem?
  private var cliRequestObserver: NSObjectProtocol?
  private var didHandleOpenEvent = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    Self.setupMenu()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let port = ShadowVMCESettings.vsockPort() {
      try? LocalRuntime.shared.setVsockPort(port)
    }
    startObservingCLIRequests()
    if handlePendingCLIRequest() {
      return
    }
    if openLastOpenedVMIfNeeded() {
      return
    }
    scheduleInitialOpenPanelIfNeeded()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let observer = cliRequestObserver {
      DistributedNotificationCenter.default().removeObserver(observer)
      cliRequestObserver = nil
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(installAgentViaUSB(_:))
      || menuItem.action == #selector(toggleHostClipboardToGuest(_:))
      || menuItem.action == #selector(toggleGuestClipboardToHost(_:))
      || menuItem.action == #selector(showVsockPortSettings(_:))
    {
      guard let controller = activeVMWindowController() else {
        if menuItem.action == #selector(installAgentViaUSB(_:)) {
          menuItem.title = "Install ShadowVMAgent"
        }
        if menuItem.action == #selector(toggleHostClipboardToGuest(_:)) {
          menuItem.state = .off
        }
        if menuItem.action == #selector(toggleGuestClipboardToHost(_:)) {
          menuItem.state = .off
        }
        return false
      }

      switch controller.virtualMachine.state {
      case .starting, .stopping:
        if menuItem.action == #selector(toggleHostClipboardToGuest(_:)) {
          menuItem.state = .off
        }
        if menuItem.action == #selector(toggleGuestClipboardToHost(_:)) {
          menuItem.state = .off
        }
        return false
      default:
        break
      }

      let vmID = controller.virtualMachine.metadata.id
      let status = LocalRuntime.shared.agentStatus(vmID: vmID)
      let installEnabled: Bool
      let clipboardEnabled: Bool
      let vsockEnabled: Bool
      let installTitle: String

      switch status {
      case .notInstalled:
        installEnabled = true
        clipboardEnabled = false
        vsockEnabled = false
        installTitle = "Install ShadowVMAgent"
      case .disconnected:
        installEnabled = true
        clipboardEnabled = false
        vsockEnabled = true
        installTitle = "Reinstall ShadowVMAgent"
      case .connected:
        installEnabled = true
        clipboardEnabled = true
        vsockEnabled = true
        installTitle = "Reinstall ShadowVMAgent"
      case nil:
        installEnabled = false
        clipboardEnabled = false
        vsockEnabled = false
        installTitle = "Install ShadowVMAgent"
      }

      if menuItem.action == #selector(toggleHostClipboardToGuest(_:)) {
        let enabled = controller.virtualMachine.metadata.agentSettings.hostClipboardToGuest
        menuItem.state = enabled ? .on : .off
        return clipboardEnabled
      }
      if menuItem.action == #selector(toggleGuestClipboardToHost(_:)) {
        let enabled = controller.virtualMachine.metadata.agentSettings.guestClipboardToHost
        menuItem.state = enabled ? .on : .off
        return clipboardEnabled
      }
      if menuItem.action == #selector(installAgentViaUSB(_:)) {
        menuItem.title = installTitle
        return installEnabled
      }
      if menuItem.action == #selector(showVsockPortSettings(_:)) {
        return vsockEnabled
      }
    }
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    cancelInitialOpenPanel()
    didHandleOpenEvent = true
    var openVMURLKeys = currentOpenVMURLKeys()
    for url in urls {
      let vmURLKey = normalizedVMURLKey(url)
      if openVMURLKeys.contains(vmURLKey) {
        presentDuplicateVMAlert()
        continue
      }
      do {
        let virtualMachine = try ShadowVMCEVMController.shared.openVirtualMachine(at: url)
        WindowController(virtualMachine: virtualMachine, controller: ShadowVMCEVMController.shared)
          .showWindow(self)
        NSDocumentController.shared.noteNewRecentDocumentURL(virtualMachine.url)
        recordLastOpenedVMPath(virtualMachine.url)
        openVMURLKeys.insert(vmURLKey)
      } catch {
        NSAlert(error: error).runModal()
      }
    }
  }

  func application(_ application: NSApplication, openFile filename: String) -> Bool {
    cancelInitialOpenPanel()
    let url = URL(fileURLWithPath: filename, isDirectory: true)
    self.application(application, open: [url])
    return true
  }

  func application(_ application: NSApplication, openFiles filenames: [String]) {
    cancelInitialOpenPanel()
    let urls = filenames.map { URL(fileURLWithPath: $0, isDirectory: true) }
    self.application(application, open: urls)
    application.reply(toOpenOrPrint: .success)
  }

  func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
    if openLastOpenedVMIfNeeded() {
      return true
    }
    presentInitialOpenPanelIfNeeded()
    return true
  }

  @objc
  func newDocument(_ sender: Any?) {
    newVirtualMachineController()?.showWindow(self)
  }

  @objc
  func openDocument(_ sender: Any?) {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    unsafeBitCast(openPanel, to: _NSSavePanel.self)._showNewDocumentButton = true
    openPanel.allowedContentTypes = UTType.vmAppleAll
    guard openPanel.runModal() == .OK else {
      return
    }
    application(NSApp, open: openPanel.urls)
  }

  private func presentInitialOpenPanelIfNeeded() {
    guard !didPresentInitialOpenPanel else {
      return
    }
    didPresentInitialOpenPanel = true
    openDocument(self)
  }

  private func scheduleInitialOpenPanelIfNeeded() {
    guard initialOpenPanelWorkItem == nil else {
      return
    }
    let workItem = DispatchWorkItem { [weak self] in
      self?.initialOpenPanelWorkItem = nil
      self?.presentInitialOpenPanelIfNeeded()
    }
    initialOpenPanelWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
  }

  private func cancelInitialOpenPanel() {
    if let workItem = initialOpenPanelWorkItem {
      workItem.cancel()
      initialOpenPanelWorkItem = nil
    }
    didPresentInitialOpenPanel = true
  }

  private func startObservingCLIRequests() {
    cliRequestObserver = DistributedNotificationCenter.default().addObserver(
      forName: ShadowVMCECLI.cliRequestNotificationName,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        self?.handleCLIRequest(notification)
      }
    }
  }

  private func handleCLIRequest(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let actionRaw = userInfo[ShadowVMCECLI.cliRequestActionKey] as? String,
      let bundlePath = userInfo[ShadowVMCECLI.cliRequestBundleKey] as? String,
      let action = ShadowVMCECLI.CLIRequestAction(rawValue: actionRaw)
    else {
      return
    }

    let url = URL(fileURLWithPath: bundlePath, isDirectory: true)
    Task { @MainActor in
      guard let windowController = self.openOrActivateVMWindow(url) else {
        return
      }
      do {
        let vm = windowController.virtualMachine!
        switch action {
        case .start:
          try await ShadowVMCEVMController.shared.start(vm)
        case .stop:
          try await ShadowVMCEVMController.shared.stop(vm)
          self.closeVMWindow(for: url)
        }
      } catch {
        NSAlert(error: error).runModal()
      }
    }
  }

  @discardableResult
  private func openOrActivateVMWindow(
    _ url: URL,
    recordLastOpened: Bool = true
  ) -> WindowController? {
    if let controller = findVMWindowController(for: url) {
      controller.window?.makeKeyAndOrderFront(self)
      NSApp.activate(ignoringOtherApps: true)
      if recordLastOpened {
        recordLastOpenedVMPath(url)
      }
      return controller
    }
    return openVMWindow(url, recordLastOpened: recordLastOpened)
  }

  private func activateVMWindow(for url: URL) -> Bool {
    let target = normalizedVMURLKey(url)
    for window in NSApp.windows {
      guard let representedURL = window.representedURL else { continue }
      if normalizedVMURLKey(representedURL) == target {
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        return true
      }
    }
    return false
  }

  private func findVMWindowController(for url: URL) -> WindowController? {
    let target = normalizedVMURLKey(url)
    for window in NSApp.windows {
      guard let representedURL = window.representedURL else { continue }
      if normalizedVMURLKey(representedURL) == target {
        return window.windowController as? WindowController
      }
    }
    return nil
  }

  private func openVMWindow(_ url: URL, recordLastOpened: Bool = true) -> WindowController? {
    let vmURLKey = normalizedVMURLKey(url)
    var openVMURLKeys = currentOpenVMURLKeys()
    if openVMURLKeys.contains(vmURLKey) {
      presentDuplicateVMAlert()
      return findVMWindowController(for: url)
    }
    do {
      let virtualMachine = try ShadowVMCEVMController.shared.openVirtualMachine(at: url)
      let controller = WindowController(
        virtualMachine: virtualMachine,
        controller: ShadowVMCEVMController.shared
      )
      controller.showWindow(self)
      NSApp.activate(ignoringOtherApps: true)
      NSDocumentController.shared.noteNewRecentDocumentURL(virtualMachine.url)
      if recordLastOpened {
        recordLastOpenedVMPath(virtualMachine.url)
      }
      openVMURLKeys.insert(vmURLKey)
      return controller
    } catch {
      NSAlert(error: error).runModal()
      return nil
    }
  }

  private func closeVMWindow(for url: URL) {
    let target = normalizedVMURLKey(url)
    for window in NSApp.windows {
      guard let representedURL = window.representedURL else { continue }
      if normalizedVMURLKey(representedURL) == target {
        window.performClose(self)
        return
      }
    }
  }

  private func handlePendingCLIRequest() -> Bool {
    guard let request = ShadowVMCECLI.consumeLaunchRequest() else {
      return false
    }
    didPresentInitialOpenPanel = true
    switch request {
    case .startVM(let url):
      _ = openOrActivateVMWindow(url)
    case .stopVM(let url):
      Task { @MainActor in
        guard let windowController = self.openOrActivateVMWindow(
          url,
          recordLastOpened: false
        ) else {
          return
        }
        do {
          let vm = windowController.virtualMachine!
          try await ShadowVMCEVMController.shared.stop(vm)
          self.closeVMWindow(for: url)
        } catch {
          NSAlert(error: error).runModal()
        }
      }
    }
    return true
  }

  @objc
  @IBAction func newWindowForTab(_ sender: Any?) {
    guard let controller = newVirtualMachineController() else {
      return
    }
    if let window = sender as? NSWindow {
      window.addTabbedWindow(controller.window!, ordered: .above)
    }
    controller.showWindow(sender)
  }

  @MainActor
  func newVirtualMachineController() -> WindowController? {
    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [.vmApple]
    guard savePanel.runModal() == .OK,
      let url = savePanel.url
    else {
      return nil
    }
    do {
      let virtualMachine = try ShadowVMCEVMController.shared.createVirtualMachine(at: url)
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
      recordLastOpenedVMPath(url)
      return WindowController(virtualMachine: virtualMachine, controller: ShadowVMCEVMController.shared)
    } catch {
      NSAlert(error: error).runModal()
      return nil
    }
  }

  private func normalizedVMURLKey(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }

  private func currentOpenVMURLKeys() -> Set<String> {
    Set(
      NSApp.windows.compactMap { window in
        guard let representedURL = window.representedURL else {
          return nil
        }
        return normalizedVMURLKey(representedURL)
      }
    )
  }

  private func recordLastOpenedVMPath(_ url: URL) {
    ShadowVMCESettings.setLastOpenedVMPath(normalizedVMURLKey(url))
  }

  private func openLastOpenedVMIfNeeded() -> Bool {
    guard !didHandleOpenEvent else { return false }
    guard currentOpenVMURLKeys().isEmpty else { return false }
    guard let path = ShadowVMCESettings.lastOpenedVMPath() else { return false }
    let url = URL(fileURLWithPath: path, isDirectory: true)
    guard FileManager.default.fileExists(atPath: url.path) else {
      ShadowVMCESettings.setLastOpenedVMPath(nil)
      return false
    }
    guard openVMWindow(url, recordLastOpened: false) != nil else {
      ShadowVMCESettings.setLastOpenedVMPath(nil)
      return false
    }
    didPresentInitialOpenPanel = true
    return true
  }

  private func presentDuplicateVMAlert() {
    let alert = NSAlert()
    alert.messageText = "This virtual machine is already running."
    alert.alertStyle = .warning
    alert.runModal()
  }

  @objc
  func openLogDirectory(_ sender: Any?) {
    let logsURL = ShadowVMConfig.shared.logsDir
    do {
      try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
      NSWorkspace.shared.activateFileViewerSelecting([logsURL])
    } catch {
      let alert = NSAlert(error: error)
      alert.messageText = "Unable to open log directory."
      alert.informativeText = "Check filesystem permissions and try again."
      alert.runModal()
    }
  }

  @objc
  func toggleHostClipboardToGuest(_ sender: NSMenuItem) {
    guard let controller = activeVMWindowController() else {
      NSSound.beep()
      return
    }
    let vm = controller.virtualMachine!
    let enabled = !vm.metadata.agentSettings.hostClipboardToGuest
    do {
      try ShadowVMCEVMController.shared.setHostClipboardToGuestEnabled(enabled, for: vm)
      sender.state = enabled ? .on : .off
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  @objc
  func toggleGuestClipboardToHost(_ sender: NSMenuItem) {
    guard let controller = activeVMWindowController() else {
      NSSound.beep()
      return
    }
    let vm = controller.virtualMachine!
    let enabled = !vm.metadata.agentSettings.guestClipboardToHost
    do {
      try ShadowVMCEVMController.shared.setGuestClipboardToHostEnabled(enabled, for: vm)
      sender.state = enabled ? .on : .off
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  @objc
  func installAgentViaUSB(_ sender: Any?) {
    guard let controller = activeVMWindowController() else {
      NSSound.beep()
      return
    }

    let vm = controller.virtualMachine!
    Task { @MainActor in
      do {
        let result = try await ShadowVMCEVMController.shared.installAgentViaUSB(for: vm)
        presentAgentInstallResult(result)
      } catch {
        NSAlert(error: error).runModal()
      }
    }
  }

  private func presentAgentInstallResult(_ result: USBMassStorageAttachResult) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "ShadowVMAgent installer ready."
    switch result {
    case .attached:
      alert.informativeText =
        "USB device attached to the guest. Open the USB volume to install ShadowVMAgent."
    case .stagedForNextStart:
      alert.informativeText =
        "USB device staged for the next start. Start the VM to mount the USB volume."
    }
    alert.runModal()
  }

  private func activeVMWindowController() -> WindowController? {
    guard let window = NSApp.keyWindow else {
      return nil
    }
    return window.windowController as? WindowController
  }

  @objc
  func showVsockPortSettings(_ sender: Any?) {
    Task { @MainActor in
      let currentPort = LocalRuntime.shared.getVsockPort()
      presentVsockPortDialog(currentPort: currentPort)
    }
  }

  private func presentVsockPortDialog(currentPort: Int) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Configure VSOCK Port"
    alert.informativeText = "Changes apply immediately. Ensure ShadowVMAgent uses the same port."
    let input = NSTextField(string: "\(currentPort)")
    input.placeholderString = "1-65535"
    input.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    alert.accessoryView = input
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }

    let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let port = Int(trimmed), port > 0, port <= 65535 else {
      presentVsockPortError("Invalid port", detail: "Enter a number between 1 and 65535.")
      return
    }

    Task { @MainActor in
      do {
        ShadowVMCESettings.setVsockPort(port)
        let updated = try LocalRuntime.shared.setVsockPort(port)
        presentVsockPortSuccess(updated)
      } catch {
        presentVsockPortError("Failed to set VSOCK port", detail: error.localizedDescription)
      }
    }
  }

  private func presentVsockPortSuccess(_ port: Int) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "VSOCK Port Updated"
    alert.informativeText = "Current port: \(port)"
    alert.runModal()
  }

  private func presentVsockPortError(_ title: String, detail: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = detail
    alert.runModal()
  }
}
