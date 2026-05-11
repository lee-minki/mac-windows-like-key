import SwiftUI

// MenuBarView 의 SwiftUI Preview.
// 별도 파일로 분리 — swiftc CLI smoke test 가 MenuBarView.swift 를 컴파일할 때
// #Preview macro 확장 문제로 빌드 깨지는 것을 회피.
//
// Xcode 빌드에서는 이 파일도 함께 컴파일되어 정상적으로 preview 제공.
// CLI smoke test 가 view 파일을 컴파일할 때는 이 파일만 제외하면 됨.

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
