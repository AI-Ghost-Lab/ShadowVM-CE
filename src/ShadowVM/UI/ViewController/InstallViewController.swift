//
//  InstallViewController.swift
//  ShadowVM
//
//  Created by Saagar Jha on 11/21/21.
//

import Cocoa

@MainActor
class InstallViewController: NSViewController, NSTextFieldDelegate {
  var virtualMachine: VirtualMachine!
  var ipswPathControl: NSPathControl!
  var diskSizeTextField: NSTextField!
  var ecidTextField: NSTextField!
  var installButton: NSButton!
  var installProgressIndicator: NSProgressIndicator!
  var installing = false

  convenience init(virtualMachine: VirtualMachine) {
    self.init()
    self.virtualMachine = virtualMachine
  }

  override func loadView() {
    let view = NSView()
    view.setAccessibilityIdentifier(AccessibilityID.Install.root)

    let ipswLabel = NSTextField(labelWithString: "IPSW:")
    ipswLabel.setAccessibilityIdentifier(AccessibilityID.Install.ipswLabel)
    ipswPathControl = NSPathControl()
    ipswPathControl.target = self
    ipswPathControl.action = #selector(ipswSelected(_:))
    ipswPathControl.isEditable = true
    ipswPathControl.pathStyle = .popUp
    ipswPathControl.setAccessibilityIdentifier(AccessibilityID.Install.ipswPath)
    if let storedPath = storedIPSWPath() {
      ipswPathControl.url = URL(fileURLWithPath: storedPath)
    }
    let ipswStackView = NSStackView(fixedSizeViews: [ipswLabel, ipswPathControl])
    ipswStackView.alignment = .firstBaseline

    let diskSizeLabel = NSTextField(labelWithString: "Disk size:")
    diskSizeLabel.setAccessibilityIdentifier(AccessibilityID.Install.diskSizeLabel)
    diskSizeTextField = NSTextField()
    diskSizeTextField.delegate = self
    diskSizeTextField.stringValue = "64"
    diskSizeTextField.setAccessibilityIdentifier(AccessibilityID.Install.diskSize)
    let diskSizeGBLabel = NSTextField(labelWithString: "GB")
    diskSizeGBLabel.setAccessibilityIdentifier(AccessibilityID.Install.diskSizeUnit)
    let diskSizeStackView = NSStackView(fixedSizeViews: [
      diskSizeLabel, diskSizeTextField, diskSizeGBLabel,
    ])
    diskSizeStackView.alignment = .firstBaseline

    let ecidLabel = NSTextField(labelWithString: "ECID:")
    ecidLabel.setAccessibilityIdentifier(AccessibilityID.Install.ecidLabel)
    ecidTextField = NSTextField()
    ecidTextField.delegate = self
    ecidTextField.isSelectable = true
    ecidTextField.stringValue = currentECID() ?? ""
    ecidTextField.setAccessibilityIdentifier(AccessibilityID.Install.ecid)
    let ecidStackView = NSStackView(fixedSizeViews: [ecidLabel, ecidTextField])
    ecidStackView.alignment = .firstBaseline

    let installStackView = NSStackView(views: [ipswStackView, diskSizeStackView, ecidStackView])
    installStackView.orientation = .vertical
    installStackView.fitContents()
    view.addSubview(installStackView)

    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.setAccessibilityIdentifier(AccessibilityID.Install.cancelButton)
    view.addSubview(cancelButton)

    installButton = NSButton(title: "Install", target: self, action: #selector(install(_:)))
    installButton.translatesAutoresizingMaskIntoConstraints = false
    installButton.keyEquivalent = "\r"
    installButton.setAccessibilityIdentifier(AccessibilityID.Install.installButton)
    view.addSubview(installButton)

    let installProgressIndicator = NSProgressIndicator()
    installProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
    installProgressIndicator.style = .bar
    installProgressIndicator.controlSize = .small
    installProgressIndicator.isIndeterminate = false
    installProgressIndicator.minValue = 0
    installProgressIndicator.maxValue = 100
    installProgressIndicator.doubleValue = 0
    installProgressIndicator.isDisplayedWhenStopped = false
    installProgressIndicator.isHidden = true
    installProgressIndicator.setAccessibilityIdentifier(AccessibilityID.Install.progress)
    view.addSubview(installProgressIndicator)
    self.installProgressIndicator = installProgressIndicator

    NSLayoutConstraint.activate([
      installStackView.leadingAnchor.constraint(
        equalToSystemSpacingAfter: view.leadingAnchor, multiplier: 1),
      view.trailingAnchor.constraint(
        equalToSystemSpacingAfter: installStackView.trailingAnchor, multiplier: 1),
      installStackView.topAnchor.constraint(
        equalToSystemSpacingBelow: view.topAnchor, multiplier: 1),
      ipswLabel.trailingAnchor.constraint(equalTo: diskSizeLabel.trailingAnchor),
      diskSizeLabel.trailingAnchor.constraint(equalTo: ecidLabel.trailingAnchor),
      ipswPathControl.widthAnchor.constraint(equalToConstant: 240),
      diskSizeTextField.widthAnchor.constraint(equalToConstant: 64),
      ecidTextField.widthAnchor.constraint(equalToConstant: 240),
      installProgressIndicator.leadingAnchor.constraint(equalTo: installStackView.leadingAnchor),
      installProgressIndicator.trailingAnchor.constraint(equalTo: installStackView.trailingAnchor),
      installProgressIndicator.topAnchor.constraint(
        equalToSystemSpacingBelow: installStackView.bottomAnchor, multiplier: 1),
      cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
      cancelButton.leadingAnchor.constraint(equalTo: installStackView.leadingAnchor),
      installButton.leadingAnchor.constraint(
        equalToSystemSpacingAfter: cancelButton.trailingAnchor, multiplier: 1),
      cancelButton.firstBaselineAnchor.constraint(equalTo: installButton.firstBaselineAnchor),
      installButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
      installButton.topAnchor.constraint(
        equalToSystemSpacingBelow: installProgressIndicator.bottomAnchor, multiplier: 1),
      view.trailingAnchor.constraint(
        equalToSystemSpacingAfter: installButton.trailingAnchor, multiplier: 1),
      view.bottomAnchor.constraint(
        equalToSystemSpacingBelow: installButton.bottomAnchor, multiplier: 1),
    ])

    validateUI()

    self.view = view
  }

  func validateUI() {
    installButton.title = installing ? "Installing..." : "Install"
    let hasConfiguration = virtualMachine.metadata.configuration != nil
    let hasIPSW = currentIPSWURL() != nil
    let hasDiskSize = parsedDiskSizeGB() != nil
    installButton.isEnabled = !installing && hasConfiguration && hasIPSW && hasDiskSize
    if !installing {
      installProgressIndicator.doubleValue = 0
    }
    installProgressIndicator.isHidden = !installing
    ipswPathControl.isEditable = !installing
    ipswPathControl.isEnabled = !installing
    diskSizeTextField.isEditable = !installing
    diskSizeTextField.isEnabled = !installing
    ecidTextField.isEditable = !installing
    ecidTextField.isEnabled = !installing
  }

  @IBAction func controlTextDidChange(_ obj: Notification) {
    validateUI()
  }

  @IBAction func ipswSelected(_ sender: NSPathControl) {
    persistIPSWPath()
    validateUI()
  }

  @IBAction func cancel(_ sender: NSButton) {
    dismiss(self)
  }

  @IBAction func install(_ sender: NSButton) {
    guard
      let ipswURL = currentIPSWURL(),
      let diskSizeGB = parsedDiskSizeGB()
    else {
      NSSound.beep()
      return
    }
    persistIPSWPath()
    let vmID = virtualMachine.metadata.id.uuidString
    let ecid = parsedECID()
    installing = true
    installProgressIndicator.doubleValue = 0
    validateUI()
    Task {
      let result = await Task {
        try await virtualMachine.install(ipsw: ipswURL, diskSize: diskSizeGB, ecid: ecid) {
          [weak self] percent in
          self?.installProgressIndicator.doubleValue = percent
          GXDLogInfo(
            "[ui-ce] install progress id=\(vmID) percent=\(Int(percent))"
          )
        }
        (view.window!.sheetParent!.windowController as! WindowController).dismiss(self)
      }.result
      if case let .failure(error) = result {
        await NSAlert(error: error).beginSheetModal(for: view.window!)
        installing = false
        validateUI()
      }
    }
  }

  private func currentIPSWURL() -> URL? {
    if let url = ipswPathControl.url {
      return url
    }
    let path = ipswPathControl.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
      return storedIPSWPathURL()
    }
    return URL(fileURLWithPath: path)
  }

  private func storedIPSWPathURL() -> URL? {
    guard let path = storedIPSWPath() else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  private func storedIPSWPath() -> String? {
    let path = virtualMachine.metadata.ui.test?.ipswPath?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let path, !path.isEmpty else {
      return nil
    }
    return path
  }

  private func persistIPSWPath() {
    let path = currentIPSWURL()?.path
    virtualMachine.updateUIIPSWPath(path)
    do {
      try virtualMachine.persistMetadata()
    } catch {
      GXDLogError(
        "[ui-ce] persist metadata failed vm=\(virtualMachine.metadata.id.uuidString) error=\(error.localizedDescription)"
      )
    }
  }

  private func parsedDiskSizeGB() -> Int? {
    let text = diskSizeTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(text), value > 0 else {
      return nil
    }
    return value
  }

  private func parsedECID() -> String? {
    let value = ecidTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  private func currentECID() -> String? {
    virtualMachine.ecidString()
  }
}
