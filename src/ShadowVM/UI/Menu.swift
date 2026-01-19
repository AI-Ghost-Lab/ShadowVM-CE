//
//  Menu.swift
//  ShadowVM
//
//  Created by Saagar Jha on 11/22/21.
//

import AppKit

let NSRecentDocumentsMenuName = unsafeBitCast(
  dlsym(dlopen(nil, RTLD_LAZY), "NSRecentDocumentsMenuName"), to: UnsafePointer<NSString>?.self)!
  .pointee

@objc protocol _NSMenu {
  var _menuName: NSString { get @objc(_setMenuName:) set }
}

@objc protocol _NSSavePanel {
  var _showNewDocumentButton: Bool { get @objc(_setShowNewDocumentButton:) set }
}

extension NSMenu {
  convenience init(title: String? = nil, items: [NSMenuItem]?) {
    defer {
      items.flatMap {
        self.items = $0
      }
    }
    guard let title = title else {
      self.init()
      return
    }
    self.init(title: title)
  }
}

extension NSMenuItem {
  convenience init(submenuTitle: String, items: [NSMenuItem]?) {
    self.init(title: submenuTitle, action: nil, keyEquivalent: "")
    submenu = NSMenu(title: submenuTitle, items: items)
  }

  convenience init(
    title: String, action: Selector? = nil, keyEquivalent: String = "",
    keyEquivalentModifierMask: NSEvent.ModifierFlags? = nil, tag: Int? = nil
  ) {
    self.init(title: title, action: action, keyEquivalent: keyEquivalent)
    keyEquivalentModifierMask.flatMap {
      self.keyEquivalentModifierMask = $0
    }
    tag.flatMap {
      self.tag = $0
    }
  }

  @discardableResult
  func applyingAccessibilityIdentifier(_ identifier: String) -> Self {
    setAccessibilityIdentifier(identifier)
    return self
  }
}

extension NSMenu {
  @discardableResult
  func applyingAccessibilityIdentifier(_ identifier: String) -> Self {
    setAccessibilityIdentifier(identifier)
    return self
  }
}

extension AppDelegate {
  static func setupMenu() {
    let appName = Bundle.main.infoDictionary!["CFBundleName"]! as! String
    let servicesMenuItem = NSMenuItem(submenuTitle: "Services", items: nil)
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.appServices)
    let openRecentMenuItem = NSMenuItem(
      submenuTitle: "Open Recent",
      items: [
        NSMenuItem(
          title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)))
        .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileOpenRecentClear)
      ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileOpenRecent)
    let windowMenuItem = NSMenuItem(
      submenuTitle: "Window",
      items: [
        NSMenuItem(
          title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        .applyingAccessibilityIdentifier(AccessibilityID.Menu.windowMinimize),
        NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)))
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.windowZoom),
        NSMenuItem.separator(),
        NSMenuItem(
          title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)))
        .applyingAccessibilityIdentifier(AccessibilityID.Menu.windowBringAllToFront),
      ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.window)
    let agentClipboardItem = NSMenuItem(
      title: "Allow Host Copy/Paste to Guest",
      action: #selector(AppDelegate.toggleHostClipboardToGuest(_:))
    )
    agentClipboardItem.target = NSApp.delegate
    agentClipboardItem.applyingAccessibilityIdentifier(
      AccessibilityID.Menu.agentSettingsClipboard)
    let agentGuestClipboardItem = NSMenuItem(
      title: "Allow Guest Copy/Paste to Host",
      action: #selector(AppDelegate.toggleGuestClipboardToHost(_:))
    )
    agentGuestClipboardItem.target = NSApp.delegate
    agentGuestClipboardItem.applyingAccessibilityIdentifier(
      AccessibilityID.Menu.agentSettingsGuestClipboard)
    let agentInstallItem = NSMenuItem(
      title: "Install ShadowVMAgent",
      action: #selector(AppDelegate.installAgentViaUSB(_:))
    )
    agentInstallItem.target = NSApp.delegate
    agentInstallItem.applyingAccessibilityIdentifier(
      AccessibilityID.Menu.agentSettingsInstallAgent)
    let editCutItem = NSMenuItem(
      title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    let editCopyItem = NSMenuItem(
      title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    let editPasteItem = NSMenuItem(
      title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    let editSelectAllItem = NSMenuItem(
      title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    NSApp.servicesMenu = servicesMenuItem.submenu
    unsafeBitCast(openRecentMenuItem.submenu, to: _NSMenu.self)._menuName =
      NSRecentDocumentsMenuName
    NSApp.windowsMenu = windowMenuItem.submenu
    NSApp.mainMenu = NSMenu(items: [
      NSMenuItem(
        submenuTitle: appName,
        items: [
          NSMenuItem(
            title: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.appAbout),
          NSMenuItem.separator(),
          servicesMenuItem,
          NSMenuItem.separator(),
          NSMenuItem(
            title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.appHide),
          NSMenuItem(
            title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h", keyEquivalentModifierMask: [.command, .option])
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.appHideOthers),
          NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)))
            .applyingAccessibilityIdentifier(AccessibilityID.Menu.appShowAll),
          NSMenuItem.separator(),
          NSMenuItem(
            title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.appQuit),
        ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.app),
      NSMenuItem(
        submenuTitle: "File",
        items: [
          NSMenuItem(
            title: "New...", action: #selector(NSDocumentController.newDocument(_:)),
            keyEquivalent: "n")
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileNew),
          NSMenuItem(
            title: "Open...", action: #selector(NSDocumentController.openDocument(_:)),
            keyEquivalent: "o")
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileOpen),
          openRecentMenuItem,
          NSMenuItem.separator(),
          NSMenuItem(title: "Run", action: #selector(ViewController.run(_:)), keyEquivalent: "r")
            .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileRun),
          NSMenuItem(title: "Stop", action: #selector(ViewController.stop(_:)), keyEquivalent: ".")
            .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileStop),
          NSMenuItem(
            title: "Hide Display", action: #selector(ViewController.toggleDisplayVisibility(_:)))
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileHideDisplay),
          NSMenuItem.separator(),
          NSMenuItem(
            title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.fileClose),
        ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.file),
      NSMenuItem(
        submenuTitle: "Settings",
        items: [
          NSMenuItem(
            title: "Set Powser Saving", action: #selector(ViewController.setPowerSavingDelay(_:)))
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.settingsPowerSaving),
        ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.settings),
      NSMenuItem(
        submenuTitle: "Debug",
        items: [
          NSMenuItem(title: "Open Log Directory", action: #selector(AppDelegate.openLogDirectory(_:)))
            .applyingAccessibilityIdentifier(AccessibilityID.Menu.debugOpenLogDirectory),
        ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.debug),
      NSMenuItem(
        submenuTitle: "Agent-Settings",
        items: [
          agentInstallItem,
          agentClipboardItem,
          agentGuestClipboardItem,
          NSMenuItem(
            title: "Configure VSOCK Port...", action: #selector(AppDelegate.showVsockPortSettings(_:)))
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.agentSettingsVsockPort),
          NSMenuItem.separator(),
          editCutItem,
          editCopyItem,
          editPasteItem,
          editSelectAllItem,
        ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.agentSettings),
      windowMenuItem,
      NSMenuItem(
        submenuTitle: "Help",
        items: [
          NSMenuItem(
            title: "Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
          .applyingAccessibilityIdentifier(AccessibilityID.Menu.helpHelp)
        ])
      .applyingAccessibilityIdentifier(AccessibilityID.Menu.help),
    ])
  }
}
