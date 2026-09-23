import Foundation

// SwiftPM's generated accessor searches beside the main bundle and then an
// absolute build-machine path. A shipped .app must use Contents/Resources.
enum AppResources {
    static let bundleName = "HymnAIrranger_HymnAIrranger.bundle"

    static var bundle: Bundle? { resolve(in: .main) }

    static func resolve(in application: Bundle) -> Bundle? {
        let locations: [URL?]
        if application.bundleURL.pathExtension == "app" {
            // Do not hide an incomplete installed app with a build-folder fallback.
            locations = [application.resourceURL]
        } else {
            // Keep swift run and Xcode's bare-executable workflow usable too.
            locations = [application.resourceURL, application.bundleURL,
                         application.executableURL?.deletingLastPathComponent(),
                         application.bundleURL.deletingLastPathComponent()]
        }
        for location in locations.compactMap({ $0 }) {
            let url = location.appendingPathComponent(bundleName, isDirectory: true)
            if let result = Bundle(url: url) { return result }
        }
        return nil
    }

    static func verifyInstalledBundle() throws {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let root = Bundle.main.resourceURL, let resources = bundle else {
            throw verificationError("The installed app resource bundle cannot be found.")
        }
        let prefix = root.resolvingSymlinksInPath().path + "/"
        let required = [("index", "html", "Web"), ("score", "js", "Web"),
                        ("verovio-toolkit-wasm", "js", "Web/Vendor"),
                        ("lame.all", "js", "Web/Vendor"),
                        ("index", "html", "Editor"), ("editor", "js", "Editor"),
                        ("smoosic", "js", "Editor/Vendor"), ("jquery", "js", "Editor/Vendor")]
        for (name, ext, directory) in required {
            guard let url = resources.url(forResource: name, withExtension: ext, subdirectory: directory),
                  url.resolvingSymlinksInPath().path.hasPrefix(prefix),
                  !(try Data(contentsOf: url)).isEmpty else {
                throw verificationError("Missing or external packaged resource: \(name).\(ext)")
            }
        }
    }

    private static func verificationError(_ message: String) -> NSError {
        NSError(domain: "HymnAIrranger.Packaging", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
