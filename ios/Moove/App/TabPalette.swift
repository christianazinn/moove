import SwiftUI

/// Each tab's color identity (decision 0050 addendum). The colors live in `Theme.Palette`.
extension TabGroup {
    var palette: Theme.Palette {
        switch self {
        case .scan: .sage
        case .items: .ochre
        case .sellBuy: .terracotta
        case .move: .teal
        case .summary: .plum
        }
    }
}
