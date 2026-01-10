import SwiftUI

struct StartWorkoutPillButton: View {
    let action: () -> Void

    var body: some View {
        AtlasPillButton("Start Workout") {
            Haptics.playLightTap()
            action()
        }
        .contentShape(RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge))
    }
}
