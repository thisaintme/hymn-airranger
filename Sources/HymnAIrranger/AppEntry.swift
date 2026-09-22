import SwiftUI
import Foundation
import Darwin

// A headless entry point allows CI to execute the actual extracted application
// without opening a window, accessing the Keychain, or creating choir projects.
@main
enum HymnAIrrangerMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--verify-resources") {
            do {
                try AppResources.verifyInstalledBundle()
                print("Installed-app resource lookup passed; all resources are inside this app.")
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(EXIT_FAILURE)
            }
        }
        HymnAIrrangerApp.main()
    }
}
