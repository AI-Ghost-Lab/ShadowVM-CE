//
//  Toolbar.swift
//  ShadowVM
//
//  Created by Saagar Jha on 11/22/21.
//

import AppKit

enum ToolbarIdentifiers: String, CaseIterable {
  case settings
  case toggleState
  case togglePauseState

  var toolbarItemIdentifier: NSToolbarItem.Identifier {
    .init(rawValue)
  }

  init?(_ rawValue: NSToolbarItem.Identifier) {
    self.init(rawValue: rawValue.rawValue)
  }
}

extension WindowController: NSToolbarDelegate {
  private func makeToolbarButtonItem(
    identifier: NSToolbarItem.Identifier,
    systemImageName: String,
    label: String,
    accessibilityIdentifier: String,
    target: AnyObject?,
    action: Selector
  ) -> NSToolbarItem {
    let toolbarItem = NSToolbarItem(itemIdentifier: identifier)
    let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: label)
    let button = NSButton(image: image ?? NSImage(), target: target, action: action)
    button.imagePosition = .imageOnly
    button.bezelStyle = .texturedRounded
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = label
    button.setAccessibilityIdentifier(accessibilityIdentifier)
    button.sizeToFit()
    toolbarItem.view = button
    toolbarItem.label = label
    toolbarItem.paletteLabel = label
    toolbarItem.toolTip = label
    toolbarItem.target = target
    toolbarItem.action = action
    return toolbarItem
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return ToolbarIdentifiers.allCases.map(\.toolbarItemIdentifier)
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch ToolbarIdentifiers(itemIdentifier)! {
    case .settings:
      return makeToolbarButtonItem(
        identifier: itemIdentifier,
        systemImageName: "gearshape",
        label: "Settings",
        accessibilityIdentifier: AccessibilityID.Toolbar.settings,
        target: viewController,
        action: #selector(viewController.openSettings(_:)))
    case .toggleState:
      return makeToolbarButtonItem(
        identifier: itemIdentifier,
        systemImageName: "play",
        label: "Run",
        accessibilityIdentifier: AccessibilityID.Toolbar.toggleState,
        target: viewController,
        action: #selector(ViewController.toggleState(_:)))
    case .togglePauseState:
      return makeToolbarButtonItem(
        identifier: itemIdentifier,
        systemImageName: "pause",
        label: "Pause",
        accessibilityIdentifier: AccessibilityID.Toolbar.togglePause,
        target: viewController,
        action: #selector(ViewController.togglePauseState(_:)))
    }
  }
}
