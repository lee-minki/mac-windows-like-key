// KeyboardLayout invariant smoke (v1.8.0)
//
// 위자드 v2 의 핵심 단위 KeyboardLayout 의 invariants 검증:
//   1. mac4key:  physicalKeys.count == 4 (Fn·Ctrl·Opt·Cmd)
//   2. mac3key:  physicalKeys.count == 3 (Ctrl·Opt·Cmd)
//   3. win3key:  physicalKeys.count == 3 (Ctrl·Opt·Cmd ← macOS 가 Win 키보드 Win→Cmd, Alt→Opt 매핑)
//   4. win4key:  physicalKeys.count == 4 (Fn·Ctrl·Opt·Cmd)
//   5. capLabels 와 physicalKeys 길이 동일 (각 행 라벨)
//   6. vdiDefaults 와 physicalKeys 길이 동일 (자동 VDI 매핑)
//   7. Mac 계열 (.mac3key, .mac4key) vdiDefaults: Cmd→Win, Opt→Alt 자동 변환
//   8. Win 계열 (.win3key, .win4key) vdiDefaults: 그대로 (이미 Win/Alt)
//   9. legendStyle 추론 (Mac vs Windows)

import Foundation
import Carbon.HIToolbox

@main
struct KeyboardLayoutSmoke {
    static func main() {
        // === Invariant 1-4: 각 layout 의 physicalKeys 갯수 ===
        guard KeyboardLayout.mac4key.physicalKeys.count == 4 else {
            print("keyboard_layout_smoke: FAIL — mac4key should have 4 physical keys")
            exit(1)
        }
        guard KeyboardLayout.mac3key.physicalKeys.count == 3 else {
            print("keyboard_layout_smoke: FAIL — mac3key should have 3 physical keys")
            exit(1)
        }
        guard KeyboardLayout.win3key.physicalKeys.count == 3 else {
            print("keyboard_layout_smoke: FAIL — win3key should have 3 physical keys")
            exit(1)
        }
        guard KeyboardLayout.win4key.physicalKeys.count == 4 else {
            print("keyboard_layout_smoke: FAIL — win4key should have 4 physical keys")
            exit(1)
        }
        print("  - Invariant 1-4 (physicalKeys counts: 4/3/3/4) ✓")

        // === Invariant 5: capLabels 와 physicalKeys 길이 동일 ===
        for layout in [KeyboardLayout.mac4key, .mac3key, .win3key, .win4key] {
            guard layout.physicalKeys.count == layout.capLabels.count else {
                print("keyboard_layout_smoke: FAIL — \(layout) capLabels/physicalKeys 길이 불일치")
                exit(1)
            }
        }
        print("  - Invariant 5 (capLabels length matches physicalKeys) ✓")

        // === Invariant 6: vdiDefaults 와 physicalKeys 길이 동일 ===
        for layout in [KeyboardLayout.mac4key, .mac3key, .win3key, .win4key] {
            guard layout.physicalKeys.count == layout.vdiDefaults.count else {
                print("keyboard_layout_smoke: FAIL — \(layout) vdiDefaults/physicalKeys 길이 불일치")
                exit(1)
            }
        }
        print("  - Invariant 6 (vdiDefaults length matches physicalKeys) ✓")

        // === Invariant 7: 3키 VDI = Ctrl·Win·Alt (mac3key + win3key 둘 다) ===
        let mac3vdi = KeyboardLayout.mac3key.vdiDefaults
        guard mac3vdi == [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)] else {
            print("keyboard_layout_smoke: FAIL — mac3key vdiDefaults should be Ctrl/Win/Alt")
            exit(1)
        }
        let win3vdi = KeyboardLayout.win3key.vdiDefaults
        guard win3vdi == [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)] else {
            print("keyboard_layout_smoke: FAIL — win3key vdiDefaults should be Ctrl/Win/Alt")
            exit(1)
        }
        print("  - Invariant 7 (3키 VDI defaults = Ctrl/Win/Alt) ✓")

        // === Invariant 8 (v1.8.1 신규): 4키 VDI = Ctrl·Win·Win·Alt (사용자 명시) ===
        let mac4vdi = KeyboardLayout.mac4key.vdiDefaults
        let expected4 = [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Command), Int64(kVK_Option)]
        guard mac4vdi == expected4 else {
            print("keyboard_layout_smoke: FAIL — mac4key vdiDefaults should be Ctrl/Win/Win/Alt, got \(mac4vdi)")
            exit(1)
        }
        let win4vdi = KeyboardLayout.win4key.vdiDefaults
        guard win4vdi == expected4 else {
            print("keyboard_layout_smoke: FAIL — win4key vdiDefaults should be Ctrl/Win/Win/Alt, got \(win4vdi)")
            exit(1)
        }
        print("  - Invariant 8 (4키 VDI defaults = Ctrl/Win/Win/Alt, v1.8.1 fix) ✓")

        // === Invariant 9: capLabels 텍스트 검증 ===
        guard KeyboardLayout.mac4key.capLabels == ["Fn", "Ctrl", "Opt", "Cmd"] else {
            print("keyboard_layout_smoke: FAIL — mac4key capLabels should be [Fn, Ctrl, Opt, Cmd]")
            exit(1)
        }
        guard KeyboardLayout.win3key.capLabels == ["Ctrl", "Win", "Alt"] else {
            print("keyboard_layout_smoke: FAIL — win3key capLabels should be [Ctrl, Win, Alt]")
            exit(1)
        }
        guard KeyboardLayout.win4key.capLabels == ["Fn", "Ctrl", "Win", "Alt"] else {
            print("keyboard_layout_smoke: FAIL — win4key capLabels should be [Fn, Ctrl, Win, Alt]")
            exit(1)
        }
        print("  - Invariant 9 (capLabels text correctness) ✓")

        // === Invariant 10: custom 은 빈 배열 (사용자 직접 정의) ===
        guard KeyboardLayout.custom.physicalKeys.isEmpty,
              KeyboardLayout.custom.capLabels.isEmpty,
              KeyboardLayout.custom.vdiDefaults.isEmpty else {
            print("keyboard_layout_smoke: FAIL — custom should have all empty arrays")
            exit(1)
        }
        print("  - Invariant 10 (custom layout empty) ✓")

        // === Invariant 11: SavedKeyboardProfile.keyboardLayout Codable round-trip ===
        let original = SavedKeyboardProfile(
            name: "Test",
            keyboardLayout: .win3key,
            physicalKeys: KeyboardLayout.win3key.physicalKeys,
            localDesiredKeys: KeyboardLayout.win3key.physicalKeys
        )
        let encoded = try? JSONEncoder().encode(original)
        guard let data = encoded,
              let decoded = try? JSONDecoder().decode(SavedKeyboardProfile.self, from: data) else {
            print("keyboard_layout_smoke: FAIL — Codable round-trip failed")
            exit(1)
        }
        guard decoded.keyboardLayout == .win3key else {
            print("keyboard_layout_smoke: FAIL — keyboardLayout not preserved through Codable")
            exit(1)
        }
        print("  - Invariant 11 (SavedKeyboardProfile.keyboardLayout Codable round-trip) ✓")

        // === Invariant 12: Legacy 호환 — keyboardLayout 없는 옛 JSON 로드 ===
        let legacyJSON = """
        {
          "name": "Legacy",
          "physicalKeys": [63, 59, 58, 55],
          "localDesiredKeys": [55, 63, 58, 59],
          "vdiDesiredKeys": [59, 55, 55, 58]
        }
        """
        guard let legacyData = legacyJSON.data(using: .utf8),
              let legacyDecoded = try? JSONDecoder().decode(SavedKeyboardProfile.self, from: legacyData) else {
            print("keyboard_layout_smoke: FAIL — Legacy JSON without keyboardLayout failed to decode")
            exit(1)
        }
        guard legacyDecoded.keyboardLayout == nil else {
            print("keyboard_layout_smoke: FAIL — Legacy profile should have nil keyboardLayout")
            exit(1)
        }
        print("  - Invariant 12 (Legacy v1.7.x profile loads with nil keyboardLayout) ✓")

        print("keyboard_layout_smoke: PASS (12 invariants)")
    }
}
