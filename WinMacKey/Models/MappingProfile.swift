import Foundation
import Carbon.HIToolbox

/// 키보드 매핑 프로파일 정의
struct MappingProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    
    // 매핑 (원본 키코드 -> 대상 키코드)
    var mappings: [Int64: Int64]
    
    /// 기본 맥북 내장 키보드용 프로파일 (변경 없음)
    static let standardMac = MappingProfile(
        name: "Standard (Mac)",
        mappings: [:]
    )
    
    /// 윈도우 블루투스 키보드 레이아웃 매핑
    /// 왼쪽 Control(0x3B) → Option(0x3A)
    /// 왼쪽 Alt(0x3A)     → Command(0x37)
    /// 왼쪽 Win(0x37)     → Control(0x3B)
    static let windowsBluetooth = MappingProfile(
        name: "Windows Bluetooth",
        mappings: [
            Int64(kVK_Control): Int64(kVK_Option),       // Ctrl -> Option
            Int64(kVK_Option): Int64(kVK_Command),       // Alt -> Command
            Int64(kVK_Command): Int64(kVK_Control)       // Win -> Control (경우에 따라 다를 수 있음)
        ]
    )
    
    /// WinMacKey의 오리지널 매핑 (Fn->Cmd, Cmd->Ctrl, Ctrl->Option, Option->Cmd)
    static let winMacKeyOriginal = MappingProfile(
        name: "WinMacKey Default",
        mappings: [
            Int64(kVK_Function): Int64(kVK_Command), // Fn -> Cmd
            Int64(kVK_Command): Int64(kVK_Control),  // Cmd -> Ctrl
            Int64(kVK_Control): Int64(kVK_Option),   // Ctrl -> Option
            Int64(kVK_Option): Int64(kVK_Command)    // Option -> Cmd
        ]
    )
    
    /// 기본 제공 프로파일 리스트
    static let defaultProfiles: [MappingProfile] = [
        .standardMac,
        .windowsBluetooth,
        .winMacKeyOriginal
    ]
}
