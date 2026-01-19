import Foundation

enum AccessibilityID {
  static let prefix = "shadowvm.ui"

  enum Window {
    static let vm = "\(prefix).window.vm"
  }

  enum VMDisplay {
    static let view = "\(prefix).vmDisplay.view"
    static let powerSavingOverlay = "\(prefix).vmDisplay.powerSavingOverlay"
    static let powerSavingLabel = "\(prefix).vmDisplay.powerSavingLabel"
  }

  enum Toolbar {
    static let settings = "\(prefix).toolbar.settings"
    static let toggleState = "\(prefix).toolbar.toggleState"
    static let togglePause = "\(prefix).toolbar.togglePause"
  }

  enum Configuration {
    static let root = "\(prefix).config.root"
    static let cpuLabel = "\(prefix).config.cpuLabel"
    static let cpuCount = "\(prefix).config.cpuCount"
    static let memoryLabel = "\(prefix).config.memoryLabel"
    static let memory = "\(prefix).config.memory"
    static let screenLabel = "\(prefix).config.screenLabel"
    static let screenWidth = "\(prefix).config.screenWidth"
    static let screenHeight = "\(prefix).config.screenHeight"
    static let screenMultiplier = "\(prefix).config.screenMultiplier"
    static let retina = "\(prefix).config.retina"
    static let screenInfo = "\(prefix).config.screenInfo"
    static let bootLabel = "\(prefix).config.bootLabel"
    static let bootRecovery = "\(prefix).config.bootRecovery"
    static let bootDFU = "\(prefix).config.bootDFU"
    static let haltLabel = "\(prefix).config.haltLabel"
    static let haltPanic = "\(prefix).config.haltPanic"
    static let haltIBoot1 = "\(prefix).config.haltIBoot1"
    static let haltIBoot2 = "\(prefix).config.haltIBoot2"
    static let debugLabel = "\(prefix).config.debugLabel"
    static let debugEnabled = "\(prefix).config.debugEnabled"
    static let debugPort = "\(prefix).config.debugPort"
    static let debugInfo = "\(prefix).config.debugInfo"
    static let saveButton = "\(prefix).config.saveButton"
  }

  enum Install {
    static let root = "\(prefix).install.root"
    static let ipswLabel = "\(prefix).install.ipswLabel"
    static let ipswPath = "\(prefix).install.ipswPath"
    static let diskSizeLabel = "\(prefix).install.diskSizeLabel"
    static let diskSize = "\(prefix).install.diskSize"
    static let diskSizeUnit = "\(prefix).install.diskSizeUnit"
    static let ecidLabel = "\(prefix).install.ecidLabel"
    static let ecid = "\(prefix).install.ecid"
    static let cancelButton = "\(prefix).install.cancelButton"
    static let installButton = "\(prefix).install.installButton"
    static let progress = "\(prefix).install.progress"
  }

  enum Menu {
    static let app = "\(prefix).menu.app"
    static let appAbout = "\(prefix).menu.app.about"
    static let appServices = "\(prefix).menu.app.services"
    static let appHide = "\(prefix).menu.app.hide"
    static let appHideOthers = "\(prefix).menu.app.hideOthers"
    static let appShowAll = "\(prefix).menu.app.showAll"
    static let appQuit = "\(prefix).menu.app.quit"

    static let file = "\(prefix).menu.file"
    static let fileNew = "\(prefix).menu.file.new"
    static let fileOpen = "\(prefix).menu.file.open"
    static let fileOpenRecent = "\(prefix).menu.file.openRecent"
    static let fileOpenRecentClear = "\(prefix).menu.file.openRecent.clear"
    static let fileRun = "\(prefix).menu.file.run"
    static let fileStop = "\(prefix).menu.file.stop"
    static let fileHideDisplay = "\(prefix).menu.file.hideDisplay"
    static let fileClose = "\(prefix).menu.file.close"

    static let edit = "\(prefix).menu.edit"
    static let editUndo = "\(prefix).menu.edit.undo"
    static let editRedo = "\(prefix).menu.edit.redo"
    static let editCut = "\(prefix).menu.edit.cut"
    static let editCopy = "\(prefix).menu.edit.copy"
    static let editPaste = "\(prefix).menu.edit.paste"
    static let editPasteMatchStyle = "\(prefix).menu.edit.pasteMatchStyle"
    static let editDelete = "\(prefix).menu.edit.delete"
    static let editSelectAll = "\(prefix).menu.edit.selectAll"

    static let editFindMenu = "\(prefix).menu.edit.find"
    static let editFind = "\(prefix).menu.edit.find.find"
    static let editFindReplace = "\(prefix).menu.edit.find.replace"
    static let editFindNext = "\(prefix).menu.edit.find.next"
    static let editFindPrevious = "\(prefix).menu.edit.find.previous"
    static let editFindUseSelection = "\(prefix).menu.edit.find.useSelection"
    static let editFindJumpToSelection = "\(prefix).menu.edit.find.jumpToSelection"

    static let editSpellingMenu = "\(prefix).menu.edit.spelling"
    static let editSpellingShow = "\(prefix).menu.edit.spelling.show"
    static let editSpellingCheckDocument = "\(prefix).menu.edit.spelling.checkDocument"
    static let editSpellingCheckWhileTyping = "\(prefix).menu.edit.spelling.checkWhileTyping"
    static let editSpellingCorrectAutomatically = "\(prefix).menu.edit.spelling.correctAutomatically"

    static let editSubstitutionsMenu = "\(prefix).menu.edit.substitutions"
    static let editSubstitutionsShow = "\(prefix).menu.edit.substitutions.show"
    static let editSubstitutionsSmartCopyPaste = "\(prefix).menu.edit.substitutions.smartCopyPaste"
    static let editSubstitutionsSmartQuotes = "\(prefix).menu.edit.substitutions.smartQuotes"
    static let editSubstitutionsSmartDashes = "\(prefix).menu.edit.substitutions.smartDashes"
    static let editSubstitutionsSmartLinks = "\(prefix).menu.edit.substitutions.smartLinks"
    static let editSubstitutionsDataDetectors = "\(prefix).menu.edit.substitutions.dataDetectors"
    static let editSubstitutionsTextReplacement = "\(prefix).menu.edit.substitutions.textReplacement"

    static let editTransformationsMenu = "\(prefix).menu.edit.transformations"
    static let editTransformationsUpper = "\(prefix).menu.edit.transformations.uppercase"
    static let editTransformationsLower = "\(prefix).menu.edit.transformations.lowercase"
    static let editTransformationsCapitalize = "\(prefix).menu.edit.transformations.capitalize"

    static let editSpeechMenu = "\(prefix).menu.edit.speech"
    static let editSpeechStart = "\(prefix).menu.edit.speech.start"
    static let editSpeechStop = "\(prefix).menu.edit.speech.stop"

    static let settings = "\(prefix).menu.settings"
    static let settingsPowerSaving = "\(prefix).menu.settings.powerSaving"

    static let debug = "\(prefix).menu.debug"
    static let debugOpenLogDirectory = "\(prefix).menu.debug.openLogDirectory"

    static let agentSettings = "\(prefix).menu.agentSettings"
    static let agentSettingsClipboard = "\(prefix).menu.agentSettings.clipboard"
    static let agentSettingsGuestClipboard = "\(prefix).menu.agentSettings.guestClipboard"
    static let agentSettingsInstallAgent = "\(prefix).menu.agentSettings.installAgent"
    static let agentSettingsVsockPort = "\(prefix).menu.agentSettings.vsockPort"

    static let window = "\(prefix).menu.window"
    static let windowMinimize = "\(prefix).menu.window.minimize"
    static let windowZoom = "\(prefix).menu.window.zoom"
    static let windowBringAllToFront = "\(prefix).menu.window.bringAllToFront"

    static let help = "\(prefix).menu.help"
    static let helpHelp = "\(prefix).menu.help.help"
  }
}
