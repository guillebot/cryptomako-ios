import SwiftUI

@main
struct CryptoMakoApp: App {
    @StateObject private var model = VaultAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
