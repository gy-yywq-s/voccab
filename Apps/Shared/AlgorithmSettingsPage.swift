import SwiftUI

/// Thin alias: per-algorithm refinement settings now live inside the merged
/// Practice Settings page (`PracticeInputPage`). Kept so existing
/// NavigationLinks and the switch-flow `goToAlgSettings` destinations still
/// compile and land on the merged page.
struct AlgorithmSettingsPage: View {
    var body: some View {
        PracticeInputPage()
    }
}
