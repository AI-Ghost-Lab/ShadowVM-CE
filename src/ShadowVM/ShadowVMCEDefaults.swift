import AppKit
import Foundation

struct ShadowVMCEDefaults {
  static let defaultScreenScale: Int = 2

  static func defaultCpuCount() -> Int {
    let hostCPU = ProcessInfo.processInfo.activeProcessorCount
    return max(1, hostCPU / 2)
  }

  static func defaultMemoryBytes() -> UInt64 {
    let totalMB = Int(ProcessInfo.processInfo.physicalMemory >> 20)
    let memoryMB = max(1024, totalMB / 2)
    return UInt64(memoryMB) * 1024 * 1024
  }

  static func defaultScreenSize() -> (width: Int, height: Int) {
    let screen = NSScreen.main ?? NSScreen.screens.first
    let fallback = (width: 1440, height: 900)
    guard let screen else { return fallback }
    let size = screen.frame.size
    return (width: Int(size.width), height: Int(size.height))
  }
}
