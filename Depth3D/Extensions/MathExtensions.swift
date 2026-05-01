import Foundation
import CoreGraphics

extension Comparable {
    /// Constrain the value to the given closed range.
    /// Defined on `Comparable` rather than per-type so it applies to Float,
    /// Double, Int, CGFloat, etc. without redeclaration. Uses `Swift.min` /
    /// `Swift.max` explicitly because `Int.min` and `CGFloat.minimum` are
    /// static *properties* that shadow the unqualified global functions
    /// inside an extension body.
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
