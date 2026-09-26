import Foundation

public enum DefinitionsBundle {
    /// Name of the SwiftPM resource bundle that carries artifacts.json.
    public static let bundleName = "Prune_PruneDefinitions.bundle"

    /// URL of the bundled artifacts.json resource.
    ///
    /// The SwiftPM-generated `Bundle.module` accessor only looks next to the
    /// executable's bundle root (`Prune.app/Prune_PruneDefinitions.bundle`) and
    /// then at an absolute `.build` path that exists only on the build machine.
    /// A signed .app cannot carry files at its root, so build.sh copies the
    /// bundle into `Contents/Resources`, which is checked first here.
    /// `Bundle.module` remains the fallback for `swift run` and `swift test`.
    public static var artifactsURL: URL {
        if let resources = Bundle.main.resourceURL {
            let candidate = resources
                .appendingPathComponent(bundleName)
                .appendingPathComponent("artifacts.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        guard let url = Bundle.module.url(forResource: "artifacts", withExtension: "json") else {
            fatalError("artifacts.json is missing from the PruneDefinitions resource bundle")
        }
        return url
    }
}
