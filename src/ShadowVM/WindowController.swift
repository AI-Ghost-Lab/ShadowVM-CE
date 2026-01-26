//
//  WindowController.swift
//  ShadowVM
//
//  Created by Saagar Jha on 11/20/21.
//

import Cocoa
import ShadowVMCore
import UniformTypeIdentifiers

@MainActor
class WindowController: NSWindowController, NSWindowDelegate {
  var retainedSelf: WindowController!
  var virtualMachine: VirtualMachine! = nil
  var viewController: ViewController!
  var vmController: ShadowVMCEVMController!
  private var isStopping = false
  private var agentStatusToken: EventBus.Token?
  private var lastAgentStatusText: String?
  private var baseTitle: String = ""

  static var cascadePoint = NSPoint.zero

  convenience init(
    virtualMachine: VirtualMachine,
    controller: ShadowVMCEVMController
  ) {
    let virtualMachineViewController = ViewController(
      virtualMachine: virtualMachine,
      controller: controller
    )

    let window = NSWindow(contentViewController: virtualMachineViewController)
    window.representedURL = virtualMachine.url
    let windowBaseTitle = virtualMachine.url.lastPathComponent
    window.title = windowBaseTitle
    window.setAccessibilityIdentifier(AccessibilityID.Window.vm)
    window.isRestorable = false
    Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)

    self.init(window: window)

    self.virtualMachine = virtualMachine
    self.viewController = virtualMachineViewController
    self.vmController = controller
    self.baseTitle = windowBaseTitle

    retainedSelf = self
    window.delegate = self

    let toolbar = NSToolbar(identifier: "MainToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = true
    window.toolbar = toolbar

    startAgentStatusUpdates()
    runSetupWorkflow()
  }

  func window(
    _ window: NSWindow,
    willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions
  ) -> NSApplication.PresentationOptions {
    return [proposedOptions, .autoHideToolbar]
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard virtualMachine.running || virtualMachine.paused else {
      return true
    }
    if isStopping {
      return false
    }
    isStopping = true
    Task {
      do {
        try await vmController.suspend(virtualMachine)
        await MainActor.run {
          isStopping = false
          sender.performClose(nil)
        }
      } catch {
        await MainActor.run {
          isStopping = false
        }
        await NSAlert(error: error).beginSheetModal(for: sender)
      }
    }
    return false
  }

  func windowWillClose(_ notification: Notification) {
    normalizeVMContentType()
    stopAgentStatusUpdates()
    vmController.close(virtualMachine)
    retainedSelf = nil
  }

  func dismiss(_ sender: NSViewController) {
    sender.presentingViewController!.dismiss(sender)
    runSetupWorkflow()
  }

  func runSetupWorkflow() {
    if virtualMachine.metadata.configuration == nil {
      viewController.presentAsSheet(
        ConfigurationViewController(
          virtualMachine: virtualMachine,
          controller: vmController
        )
      )
    } else if !virtualMachine.metadata.installed {
      viewController.presentAsSheet(InstallViewController(virtualMachine: virtualMachine))
    }
  }

  private func startAgentStatusUpdates() {
    refreshAgentStatusTitle()
    guard agentStatusToken == nil else { return }
    agentStatusToken = LocalRuntime.shared.addEventHandler { [weak self] event in
      guard case let .agentStatusChanged(vmID, status, _) = event else { return }
      guard let self, vmID == self.virtualMachine.metadata.id else { return }
      Task { @MainActor in
        self.refreshAgentStatusTitle(status: status)
      }
    }
  }

  private func stopAgentStatusUpdates() {
    if let token = agentStatusToken {
      LocalRuntime.shared.removeEventHandler(token)
    }
    agentStatusToken = nil
  }

  private func refreshAgentStatusTitle() {
    let statusText = resolveAgentStatusText(status: LocalRuntime.shared.agentStatus(
      vmID: virtualMachine.metadata.id))
    guard statusText != lastAgentStatusText else { return }
    lastAgentStatusText = statusText
    window?.title = "\(baseTitle) - Agent: \(statusText)"
  }

  private func refreshAgentStatusTitle(status: AgentStatus) {
    let statusText = resolveAgentStatusText(status: status)
    guard statusText != lastAgentStatusText else { return }
    lastAgentStatusText = statusText
    window?.title = "\(baseTitle) - Agent: \(statusText)"
  }

  private func resolveAgentStatusText(status: AgentStatus?) -> String {
    switch status {
    case .notInstalled:
      return "Not Installed"
    case .disconnected:
      return "Disconnected"
    case .connected:
      return "Connected"
    case nil:
      return "Unknown"
    }
  }

  private func normalizeVMContentType() {
    let url = virtualMachine.url
    if let values = try? url.resourceValues(forKeys: [.contentTypeKey, .typeIdentifierKey]) {
      let currentIdentifier = values.contentType?.identifier ?? values.typeIdentifier
      if currentIdentifier == UTType.vmApple.identifier {
        return
      }
    }
    do {
      try (url as NSURL).setResourceValue(
        UTType.vmApple.identifier,
        forKey: URLResourceKey.typeIdentifierKey
      )
      GXDLogDebug(
        "[ui-ce] normalize content type vm=\(virtualMachine.metadata.id.uuidString) uti=\(UTType.vmApple.identifier)"
      )
    } catch {
      GXDLogDebug(
        "[ui-ce] normalize content type failed vm=\(virtualMachine.metadata.id.uuidString) error=\(error.localizedDescription)"
      )
    }
  }
}
