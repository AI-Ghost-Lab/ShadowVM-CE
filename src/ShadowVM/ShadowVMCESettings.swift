import Foundation
import ShadowVMCore

enum ShadowVMCESettings {
  private static let settingsFileName = "settings.json"
  private static let lastOpenedVMPathKey = "lastOpenedVMPath"
  private static let vsockPortKey = "vsock_port"

  static func lastOpenedVMPath() -> String? {
    let settings = readSettings()
    guard let value = settings[lastOpenedVMPathKey] as? String, !value.isEmpty else {
      return nil
    }
    return value
  }

  static func setLastOpenedVMPath(_ path: String?) {
    var settings = readSettings()
    if let path, !path.isEmpty {
      settings[lastOpenedVMPathKey] = path
    } else {
      settings.removeValue(forKey: lastOpenedVMPathKey)
    }
    writeSettings(settings)
  }

  static func vsockPort() -> Int? {
    let settings = readSettings()
    switch settings[vsockPortKey] {
    case let number as NSNumber:
      return number.intValue
    case let string as String:
      return Int(string)
    default:
      return nil
    }
  }

  static func setVsockPort(_ port: Int?) {
    var settings = readSettings()
    if let port {
      settings[vsockPortKey] = port
    } else {
      settings.removeValue(forKey: vsockPortKey)
    }
    writeSettings(settings)
  }

  private static func readSettings() -> [String: Any] {
    let url = settingsURL()
    guard let data = try? Data(contentsOf: url) else {
      return [:]
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data, options: []),
      let dict = object as? [String: Any]
    else {
      return [:]
    }
    return dict
  }

  private static func writeSettings(_ settings: [String: Any]) {
    do {
      let homeDir = ShadowVMConfig.shared.homeDir
      try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
      let data = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
      try data.write(to: settingsURL(), options: .atomic)
    } catch {
      return
    }
  }

  private static func settingsURL() -> URL {
    ShadowVMConfig.shared.homeDir.appendingPathComponent(settingsFileName)
  }
}
