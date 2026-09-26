import Foundation

public enum DefinitionsBundle {
    /// URL of the bundled artifacts.json resource.
    public static var artifactsURL: URL {
        guard let url = Bundle.module.url(forResource: "artifacts", withExtension: "json") else {
            fatalError("artifacts.json is missing from the PruneDefinitions resource bundle")
        }
        return url
    }
}
