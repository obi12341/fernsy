@_exported import FernsyShared
import Foundation

extension Bundle {
    /// The package's own resources (its string catalog), also for its tests, whose
    /// `Bundle.module` is the test bundle.
    static var fernsyCore: Bundle { .module }
}
