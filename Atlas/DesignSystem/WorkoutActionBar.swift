import SwiftUI

struct WorkoutActionBar: View {
    struct Action {
        let title: String
        let role: ButtonRole?
        let action: () -> Void

        init(title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.role = role
            self.action = action
        }
    }

    let left: Action
    let right: Action

    var body: some View {
        HStack(spacing: AppStyle.sectionSpacing) {
            AtlasPillButton(left.title, role: left.role, action: left.action)
                .frame(maxWidth: .infinity)
            AtlasPillButton(right.title, role: right.role, action: right.action)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppStyle.glassContentPadding)
        .padding(.vertical, AppStyle.glassContentPadding * 0.75)
        .padding(.horizontal, AppStyle.screenHorizontalPadding)
        .padding(.bottom, AppStyle.startButtonBottomPadding)
    }
}
