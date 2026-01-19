//
//  ViewController.swift
//  ShadowVM
//
//  Created by Saagar Jha on 11/20/21.
//

import Cocoa
import ShadowVMCore

@MainActor
class ViewController: NSViewController, NSToolbarItemValidation, NSMenuItemValidation {
  var virtualMachine: VirtualMachine!
  var vmController: ShadowVMCEVMController!
  var virtualMachineView: VMDisplayView!
  private var trackingArea: NSTrackingArea?
  private weak var trackingAreaContainer: NSView?
  private var powerSavingDelaySeconds: UInt64 = ViewController.defaultPowerSavingDelaySeconds
  private var powerSavingSuppressed = false
  private var autoPaused = false
  private var autoPauseTask: Task<Void, Never>?
  private var pauseOverlayView: NSVisualEffectView?
  private var windowHidden = false
  private var stateObserver: NSObjectProtocol?
  private var lastValidationLog: Date = .distantPast
  private static let defaultPowerSavingDelaySeconds: UInt64 = 180

  private var isPowerSavingEnabled: Bool {
    powerSavingDelaySeconds > 0 && !powerSavingSuppressed
  }

  convenience init(virtualMachine: VirtualMachine, controller: ShadowVMCEVMController) {
    self.init()
    self.virtualMachine = virtualMachine
    vmController = controller
  }

  deinit {
    if let observer = stateObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  override func loadView() {
    setupVirtualMachineView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    startObservingStateChanges()
  }

  func setupVirtualMachineView() {
    let virtualMachineView = VMDisplayView()
    virtualMachineView.capturesSystemKeys = true
    virtualMachineView.setAccessibilityIdentifier(AccessibilityID.VMDisplay.view)
    virtualMachineView.frame.size =
      self.virtualMachineView?.frame.size ?? NSSize(width: 640, height: 400)
    self.virtualMachineView = virtualMachineView
    view = virtualMachineView
    setupPauseOverlay()
  }

  private func bindVirtualMachineView() {
    virtualMachineView.bind(to: virtualMachine)
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    installTrackingArea()
    refreshRunningView()
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    removeTrackingArea()
  }

  private func setupPauseOverlay() {
    let overlay = NSVisualEffectView()
    overlay.translatesAutoresizingMaskIntoConstraints = false
    overlay.material = .hudWindow
    overlay.blendingMode = .withinWindow
    overlay.state = .active
    overlay.isHidden = true
    overlay.alphaValue = 0
    overlay.setAccessibilityIdentifier(AccessibilityID.VMDisplay.powerSavingOverlay)

    let label = NSTextField(labelWithString: "Power Saving...")
    label.textColor = .labelColor
    label.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    label.setAccessibilityIdentifier(AccessibilityID.VMDisplay.powerSavingLabel)

    overlay.addSubview(label)
    virtualMachineView.addSubview(overlay)

    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: virtualMachineView.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: virtualMachineView.trailingAnchor),
      overlay.topAnchor.constraint(equalTo: virtualMachineView.topAnchor),
      overlay.bottomAnchor.constraint(equalTo: virtualMachineView.bottomAnchor),

      label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
    ])

    let clickRecognizer = NSClickGestureRecognizer(
      target: self, action: #selector(handleOverlayClick(_:)))
    overlay.addGestureRecognizer(clickRecognizer)

    pauseOverlayView = overlay
  }

  private func startObservingStateChanges() {
    let vmID = virtualMachine.metadata.id
    stateObserver = NotificationCenter.default.addObserver(
      forName: .shadowVMCEVMStateDidChange,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let self,
        let id = notification.userInfo?["id"] as? UUID,
        id == vmID
      else {
        return
      }
      Task { @MainActor in
        self.updatePauseOverlayVisibility()
        self.refreshRunningView()
        self.refreshToolbarItems()
        self.view.window?.toolbar?.validateVisibleItems()
      }
    }
  }

  private func installTrackingArea() {
    guard let container = view.window?.contentView?.superview ?? view.window?.contentView else {
      return
    }
    removeTrackingArea()
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
    container.addTrackingArea(trackingArea)
    self.trackingArea = trackingArea
    trackingAreaContainer = container
  }

  private func removeTrackingArea() {
    if let trackingArea, let container = trackingAreaContainer {
      container.removeTrackingArea(trackingArea)
    }
    cancelScheduledAutoPause()
    trackingArea = nil
    trackingAreaContainer = nil
  }

  private func scheduleAutoPause() {
    cancelScheduledAutoPause()
    guard powerSavingDelaySeconds > 0 else { return }
    autoPauseTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await Task.sleep(nanoseconds: self.powerSavingDelaySeconds * 1_000_000_000)
        self.autoPauseIfNeeded()
      } catch {
        // Cancelled or interrupted; ignore.
      }
    }
  }

  private func cancelScheduledAutoPause() {
    autoPauseTask?.cancel()
    autoPauseTask = nil
  }

  private func autoPauseIfNeeded() {
    guard isPowerSavingEnabled, virtualMachine.running, !virtualMachine.paused, !autoPaused else {
      return
    }
    autoPaused = true
    Task { @MainActor in
      do {
        try await virtualMachine.pause()
        updatePauseOverlayVisibility()
        view.window!.toolbar!.validateVisibleItems()
      } catch {
        autoPaused = false
        throw error
      }
    }.presentErrorIfNecessary(window: view.window!)
  }

  private func autoResumeIfNeeded() {
    guard isPowerSavingEnabled, autoPaused, virtualMachine.running else {
      return
    }
    let previousAutoPaused = autoPaused
    autoPaused = false
    Task { @MainActor in
      do {
        try await virtualMachine.resume()
        updatePauseOverlayVisibility()
        view.window!.toolbar!.validateVisibleItems()
      } catch {
        autoPaused = previousAutoPaused
        throw error
      }
    }.presentErrorIfNecessary(window: view.window!)
  }

  private func updatePauseOverlayVisibility(animated: Bool = true) {
    guard let overlay = pauseOverlayView else {
      return
    }

    let shouldShow = virtualMachine.paused
    let targetAlpha: CGFloat = shouldShow ? 0.35 : 0
    let applyVisibility = {
      overlay.alphaValue = targetAlpha
    }

    if animated {
      overlay.isHidden = false
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        applyVisibility()
      } completionHandler: {
        overlay.isHidden = !shouldShow
      }
    } else {
      applyVisibility()
      overlay.isHidden = !shouldShow
    }
  }

  @objc private func handleOverlayClick(_ sender: Any?) {
    guard virtualMachine.paused else {
      return
    }
    cancelScheduledAutoPause()
    resume(sender)
  }

  override func mouseEntered(with event: NSEvent) {
    cancelScheduledAutoPause()
    autoResumeIfNeeded()
  }

  override func mouseExited(with event: NSEvent) {
    scheduleAutoPause()
  }

  @IBAction func toggleDisplayVisibility(_ sender: Any?) {
    guard let window = view.window else {
      return
    }

    windowHidden.toggle()

    if windowHidden {
      window.makeFirstResponder(nil)
      window.isOpaque = false
      window.alphaValue = 0
      window.ignoresMouseEvents = true
      NSApp.deactivate()
    } else {
      window.alphaValue = 1
      window.isOpaque = true
      window.ignoresMouseEvents = false
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(self)
      virtualMachineView.focus(in: window)
    }

    if let menuItem = sender as? NSMenuItem {
      menuItem.title = windowHidden ? "Show Window" : "Hide Window"
    }
  }

  @IBAction func openSettings(_ sender: NSToolbarItem) {
    presentAsSheet(
      ConfigurationViewController(
        virtualMachine: virtualMachine,
        controller: vmController
      )
    )
  }

  @IBAction func toggleState(_ sender: NSToolbarItem) {
    if virtualMachine.metadata.installed {
      (!virtualMachine.running ? run : stop)(sender)
    } else {
      presentAsSheet(InstallViewController(virtualMachine: virtualMachine))
    }
  }

  @IBAction func togglePauseState(_ sender: NSToolbarItem) {
    guard virtualMachine.running else {
      return
    }
    (virtualMachine.paused ? resume : pause)(sender)
  }

  @IBAction func setPowerSavingDelay(_ sender: Any?) {
    presentPowerSavingDelayDialog()
  }

  private func presentPowerSavingDelayDialog() {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Set Powser Saving"
    alert.informativeText = "Delay in seconds before auto-pause. Enter 0 to disable."
    let input = NSTextField(string: "\(powerSavingDelaySeconds)")
    input.placeholderString = "0-86400"
    input.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    alert.accessoryView = input
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }

    let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let delay = UInt64(trimmed) else {
      presentPowerSavingDelayError("Invalid value", detail: "Enter a whole number in seconds.")
      return
    }
    applyPowerSavingDelay(delay)
  }

  private func presentPowerSavingDelayError(_ title: String, detail: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = detail
    alert.runModal()
  }

  private func applyPowerSavingDelay(_ delay: UInt64) {
    powerSavingDelaySeconds = delay
    cancelScheduledAutoPause()
    if delay == 0, autoPaused, virtualMachine.running, virtualMachine.paused {
      autoPaused = false
      resume(nil)
    }
  }

  @IBAction func run(_ sender: Any?) {
    Task { @MainActor in
      cancelScheduledAutoPause()
      logUIState("run begin")
      // During boot, keep power saving disabled; enable after start completes.
      powerSavingSuppressed = true
      defer { powerSavingSuppressed = false }
      if let configuration = virtualMachine.metadata.configuration {
        view.window!.contentAspectRatio = NSSize(
          width: configuration.screenWidth, height: configuration.screenHeight)
      }
      setupVirtualMachineView()
      try await vmController.start(virtualMachine)
      bindVirtualMachineView()
      logUIState("run end")
      autoPaused = false
      updatePauseOverlayVisibility(animated: false)
      refreshToolbarItems()
      view.window!.toolbar!.validateVisibleItems()
    }.presentErrorIfNecessary(window: view.window!)
  }

  @IBAction func stop(_ sender: Any?) {
    Task { @MainActor in
      try await vmController.stop(virtualMachine)
      logUIState("stop end")
      powerSavingSuppressed = false
      autoPaused = false
      cancelScheduledAutoPause()
      updatePauseOverlayVisibility()
      refreshToolbarItems()
      view.window!.toolbar!.validateVisibleItems()
    }.presentErrorIfNecessary(window: view.window!)
  }

  @IBAction func pause(_ sender: Any?) {
    autoPaused = false
    cancelScheduledAutoPause()
    Task { @MainActor in
      try await vmController.pause(virtualMachine)
      logUIState("pause end")
      updatePauseOverlayVisibility()
      refreshToolbarItems()
      view.window!.toolbar!.validateVisibleItems()
    }.presentErrorIfNecessary(window: view.window!)
  }

  @IBAction func resume(_ sender: Any?) {
    Task { @MainActor in
      try await vmController.resume(virtualMachine)
      logUIState("resume end")
      autoPaused = false
      cancelScheduledAutoPause()
      updatePauseOverlayVisibility()
      refreshToolbarItems()
      view.window!.toolbar!.validateVisibleItems()
    }.presentErrorIfNecessary(window: view.window!)
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(run(_:)):
      return !virtualMachine.running
    case #selector(stop(_:)):
      return virtualMachine.running
    case #selector(setPowerSavingDelay(_:)):
      menuItem.state = powerSavingDelaySeconds > 0 ? .on : .off
      return true
    case #selector(toggleDisplayVisibility(_:)):
      menuItem.title = windowHidden ? "Show Window" : "Hide Window"
      return true
    default:
      preconditionFailure()
    }
  }

  func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
    logValidationIfNeeded(item)
    return updateToolbarItemState(item, identifier: ToolbarIdentifiers(item.itemIdentifier)!)
  }

  private func updateToolbarItem(
    _ item: NSToolbarItem, systemImageName: String, label: String
  ) {
    let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: label)
    item.image = image
    item.label = label
    item.paletteLabel = label
    item.toolTip = label
    if let button = item.view as? NSButton {
      button.image = image
      button.toolTip = label
      button.setAccessibilityLabel(label)
    }
  }

  private func updateToolbarItemEnabledState(_ item: NSToolbarItem, isEnabled: Bool) {
    item.isEnabled = isEnabled
    if let control = item.view as? NSControl {
      control.isEnabled = isEnabled
    }
  }

  private func refreshRunningView() {
    guard virtualMachine.running || virtualMachine.paused else {
      return
    }
    if let configuration = virtualMachine.metadata.configuration {
      view.window?.contentAspectRatio = NSSize(
        width: configuration.screenWidth, height: configuration.screenHeight)
    }
    bindVirtualMachineView()
  }

  private func refreshToolbarItems() {
    guard let items = view.window?.toolbar?.items else {
      return
    }
    for item in items {
      guard let identifier = ToolbarIdentifiers(item.itemIdentifier) else {
        continue
      }
      _ = updateToolbarItemState(item, identifier: identifier)
    }
  }

  @discardableResult
  private func updateToolbarItemState(
    _ item: NSToolbarItem,
    identifier: ToolbarIdentifiers
  ) -> Bool {
    switch identifier {
    case .settings:
      let isEnabled = !virtualMachine.running
      updateToolbarItemEnabledState(item, isEnabled: isEnabled)
      return isEnabled
    case .toggleState:
      let label = virtualMachine.running ? "Stop" : "Run"
      let systemImageName = virtualMachine.running ? "stop" : "play"
      updateToolbarItem(item, systemImageName: systemImageName, label: label)
      view.window?.isDocumentEdited = virtualMachine.running
      let isEnabled = true
      updateToolbarItemEnabledState(item, isEnabled: isEnabled)
      return isEnabled
    case .togglePauseState:
      if virtualMachine.running {
        let label = virtualMachine.paused ? "Resume" : "Pause"
        let systemImageName = virtualMachine.paused ? "play" : "pause"
        updateToolbarItem(item, systemImageName: systemImageName, label: label)
        let isEnabled = true
        updateToolbarItemEnabledState(item, isEnabled: isEnabled)
        return isEnabled
      }
      updateToolbarItem(item, systemImageName: "pause", label: "Pause")
      let isEnabled = false
      updateToolbarItemEnabledState(item, isEnabled: isEnabled)
      return isEnabled
    }
  }

  private func logUIState(_ context: String) {
    GXDLogInfo(
      "[ui-ce] \(context) id=\(virtualMachine.metadata.id.uuidString) running=\(virtualMachine.running) paused=\(virtualMachine.paused) installed=\(virtualMachine.metadata.installed)"
    )
  }

  private func logValidationIfNeeded(_ item: NSToolbarItem) {
    let now = Date()
    guard now.timeIntervalSince(lastValidationLog) >= 0.5 else {
      return
    }
    lastValidationLog = now
    let identifier = item.itemIdentifier.rawValue
    GXDLogInfo(
      "[ui-ce] validate item=\(identifier) running=\(virtualMachine.running) paused=\(virtualMachine.paused) installed=\(virtualMachine.metadata.installed)"
    )
  }
}

extension Task where Success == Void, Failure == Error {
  func presentErrorIfNecessary(window: NSWindow) {
    Task { @MainActor in
      do {
        try await value
      } catch {
        await NSAlert(error: error).beginSheetModal(for: window)
      }
    }
  }
}
