#if !canImport(Darwin)
import Foundation

// Fernsy Server shows no translated texts: on Linux the English keys stand for themselves.
extension String {
    init(localized key: String, bundle: Bundle) {
        self = key
    }
}

extension Bundle {
    static var module: Bundle { .main }
}
#endif
