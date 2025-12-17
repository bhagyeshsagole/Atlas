import SwiftUI

struct AddButton: View {
    /// VISUAL TWEAK: Change `buttonSize` to adjust tap target + visual weight.
    private let buttonSize: CGFloat = 56
    /// VISUAL TWEAK: Change `iconSize` to make the plus feel lighter/heavier.
    private let iconSize: CGFloat = 22
    /// VISUAL TWEAK: Change corner radius to match iOS 26 glass vibe.
    private let cornerRadius: CGFloat = 18

    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: buttonSize, height: buttonSize, alignment: .center)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.white.opacity(colorScheme == .dark ? AppStyle.headerButtonFillOpacityDark : AppStyle.headerButtonFillOpacityLight))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(AppStyle.headerButtonStrokeOpacity), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }
}
