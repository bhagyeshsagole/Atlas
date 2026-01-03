//
//  AppStyle.swift
//  Atlas
//
//  Overview: Design tokens for typography, spacing, and glass styling.
//
//  Update: Hardening pass to align typography scales, header hit areas, and popup sizing/animation.

import SwiftUI

enum AppTypeScale {
    case brand
    case title
    case title3
    case section
    case body
    case footnote
    case caption
    case pill
}

enum AppStyle {
    /// DEV MAP: Global typography/spacing tokens live here.
    /// VISUAL TWEAK: Change `fontBump` to raise or lower every type size globally at once.
    /// VISUAL TWEAK: Increase for a larger overall scale; decrease to tighten all text.
    static let fontBump: CGFloat = 2

    /// VISUAL TWEAK: Change `brandBaseSize` to adjust the Atlas wordmark scale before the global bump.
    /// VISUAL TWEAK: Combine with `fontBump` to resize all brand headers together.
    static let brandBaseSize: CGFloat = 26

    /// VISUAL TWEAK: Change `titleBaseSize` to resize primary titles before the global bump.
    /// VISUAL TWEAK: Use this when section headers across the app feel too large/small.
    static let titleBaseSize: CGFloat = 22

    /// VISUAL TWEAK: Change `sectionBaseSize` to resize uppercase section labels.
    /// VISUAL TWEAK: Adjust for tighter or louder grouping labels across Settings and Home.
    static let sectionBaseSize: CGFloat = 12

    /// VISUAL TWEAK: Change `title3BaseSize` to resize secondary headings between title and body.
    /// VISUAL TWEAK: Raise for louder mid-headlines; lower for calmer subheads.
    static let title3BaseSize: CGFloat = 18

    /// VISUAL TWEAK: Change `bodyBaseSize` to resize standard body text.
    /// VISUAL TWEAK: Use this to affect most rows and descriptive copy at once.
    static let bodyBaseSize: CGFloat = 14

    /// VISUAL TWEAK: Change `footnoteBaseSize` to resize small helper text.
    /// VISUAL TWEAK: Lower for quieter notes; raise for more legibility.
    static let footnoteBaseSize: CGFloat = 12

    /// VISUAL TWEAK: Change `captionBaseSize` to resize captions and helper text.
    /// VISUAL TWEAK: Bump up for more legibility on small notes.
    static let captionBaseSize: CGFloat = 12

    /// VISUAL TWEAK: Change `pillBaseSize` to resize pill/button labels.
    /// VISUAL TWEAK: Increase for chunkier CTAs; decrease for subtler pills.
    static let pillBaseSize: CGFloat = 18

    /// VISUAL TWEAK: Change `brandWeight` to alter the Atlas wordmark thickness globally.
    /// VISUAL TWEAK: Use `.semibold` for lighter branding or `.black` for heavier emphasis.
    static let brandWeight: Font.Weight = .bold

    /// VISUAL TWEAK: Change `titleWeight` to alter title emphasis.
    /// VISUAL TWEAK: Match this to your preferred hierarchy strength for headings.
    static let titleWeight: Font.Weight = .semibold

    /// VISUAL TWEAK: Change `title3Weight` to alter secondary heading emphasis.
    /// VISUAL TWEAK: Use `.medium` for softer mid-headlines or `.bold` for stronger emphasis.
    static let title3Weight: Font.Weight = .semibold

    /// VISUAL TWEAK: Change `sectionWeight` to alter section label emphasis.
    /// VISUAL TWEAK: Drop to `.medium` for calmer dividers, raise to `.bold` for stronger grouping.
    static let sectionWeight: Font.Weight = .bold

    /// VISUAL TWEAK: Change `bodyWeight` to alter default body emphasis.
    /// VISUAL TWEAK: Use `.regular` for casual text or `.medium` for denser text.
    static let bodyWeight: Font.Weight = .regular

    /// VISUAL TWEAK: Change `footnoteWeight` to adjust helper text emphasis.
    /// VISUAL TWEAK: Increase for more contrast on small helper labels.
    static let footnoteWeight: Font.Weight = .regular

    /// VISUAL TWEAK: Change `captionWeight` to alter helper text emphasis.
    /// VISUAL TWEAK: Increase for more contrast on small labels.
    static let captionWeight: Font.Weight = .regular

    /// VISUAL TWEAK: Change `pillWeight` to alter CTA label emphasis.
    /// VISUAL TWEAK: Use `.semibold` for balanced pills or `.bold` for louder ones.
    static let pillWeight: Font.Weight = .semibold

    /// VISUAL TWEAK: Change `brandItalic` to toggle italics on the Atlas wordmark.
    /// VISUAL TWEAK: Set to `false` for straight branding or keep `true` for motion.
    static let brandItalic: Bool = true

    /// VISUAL TWEAK: Change `sectionLetterCaseUppercased` to toggle uppercase styling for section labels.
    /// VISUAL TWEAK: Set to `false` for sentence-case sections across the app.
    static let sectionLetterCaseUppercased: Bool = true

    /// VISUAL TWEAK: Change `screenHorizontalPadding` to widen or tighten default screen gutters.
    /// VISUAL TWEAK: Raising this pads content inward across Home, Settings, and Workout.
    static let screenHorizontalPadding: CGFloat = 20

    /// VISUAL TWEAK: Change `screenTopPadding` to shift content down from safe areas.
    /// VISUAL TWEAK: Increase if headers feel cramped under the status bar.
    static let screenTopPadding: CGFloat = 12

    /// VISUAL TWEAK: Change `headerTopPadding` to offset top bars like Home/Settings headers.
    /// VISUAL TWEAK: Lower for tighter headers, raise to add breathing room.
    static let headerTopPadding: CGFloat = 6

    /// VISUAL TWEAK: Change `sectionSpacing` to adjust default vertical spacing between groups.
    /// VISUAL TWEAK: Increase for airier stacks; decrease to condense layouts.
    static let sectionSpacing: CGFloat = 20

    /// VISUAL TWEAK: Change `contentPaddingLarge` to adjust default large padding around full-screen stacks.
    /// VISUAL TWEAK: Increase for wider gutters; decrease for tighter layouts.
    static let contentPaddingLarge: CGFloat = 24

    /// VISUAL TWEAK: Change `cardContentSpacing` to adjust vertical spacing inside cards.
    /// VISUAL TWEAK: Increase for looser card content; decrease for denser stacks.
    static let cardContentSpacing: CGFloat = 16

    /// VISUAL TWEAK: Change `subheaderSpacing` to adjust tight spacing between header text lines.
    /// VISUAL TWEAK: Use smaller values to pull titles and subtitles closer.
    static let subheaderSpacing: CGFloat = 6

    /// VISUAL TWEAK: Change `pillContentSpacing` to adjust icon/text spacing inside pills.
    /// VISUAL TWEAK: Increase for more separation between glyphs and labels.
    static let pillContentSpacing: CGFloat = 10

    /// VISUAL TWEAK: Change `brandPaddingHorizontal` to adjust left/right padding around the Atlas wordmark.
    /// VISUAL TWEAK: Increase for a chunkier hit target; decrease for a tighter chip.
    static let brandPaddingHorizontal: CGFloat = 6

    /// VISUAL TWEAK: Change `brandPaddingVertical` to adjust top/bottom padding around the Atlas wordmark.
    /// VISUAL TWEAK: Increase to make the brand chip taller; decrease to flatten it.
    static let brandPaddingVertical: CGFloat = 10

    /// VISUAL TWEAK: Change `calendarHeaderSpacing` to adjust spacing between month title and badges.
    /// VISUAL TWEAK: Increase to separate elements; decrease to tighten the header row.
    static let calendarHeaderSpacing: CGFloat = 8

    /// VISUAL TWEAK: Change `calendarColumnSpacing` to adjust spacing between weekday columns.
    /// VISUAL TWEAK: Increase for wider columns; decrease for a tighter calendar grid.
    static let calendarColumnSpacing: CGFloat = 6

    /// VISUAL TWEAK: Change `calendarGridSpacing` to alter day-to-day spacing in the month grid.
    /// VISUAL TWEAK: Increase for more breathing room around cells; decrease for denser calendars.
    static let calendarGridSpacing: CGFloat = 10

    /// VISUAL TWEAK: Change `cardRevealOffset` to adjust how far cards slide during entrance animations.
    /// VISUAL TWEAK: Increase for a more pronounced rise; decrease for a subtler entrance.
    static let cardRevealOffset: CGFloat = 8

    /// VISUAL TWEAK: Change `calendarTodayHeight` to adjust placeholder height for empty days.
    /// VISUAL TWEAK: Increase if the grid feels cramped; decrease for a flatter calendar.
    static let calendarTodayHeight: CGFloat = 32

    /// VISUAL TWEAK: Change `calendarDayMinHeight` to adjust minimum height for each day cell.
    /// VISUAL TWEAK: Increase for taller cells; decrease to compact the calendar.
    static let calendarDayMinHeight: CGFloat = 54

    /// VISUAL TWEAK: Change `calendarDayVerticalPadding` to adjust top/bottom padding of each day number.
    /// VISUAL TWEAK: Increase for taller number chips; decrease for flatter chips.
    static let calendarDayVerticalPadding: CGFloat = 7

    /// VISUAL TWEAK: Change `calendarDayCornerRadius` to adjust rounding of each day chip.
    /// VISUAL TWEAK: Increase for softer day pills; decrease for squarer chips.
    static let calendarDayCornerRadius: CGFloat = 12

    /// VISUAL TWEAK: Change `calendarWorkoutDotSize` to adjust the size of workout indicator bubbles.
    /// VISUAL TWEAK: Increase for more prominent dots; decrease for subtler markers.
    static let calendarWorkoutDotSize: CGFloat = 10

    /// VISUAL TWEAK: Change `calendarDayTextOpacityToday` to adjust emphasis on today's date.
    /// VISUAL TWEAK: Increase for brighter emphasis; decrease for subtler contrast.
    static let calendarDayTextOpacityToday: Double = 0.95

    /// VISUAL TWEAK: Change `calendarDayTextOpacityDefault` to adjust emphasis on normal dates.
    /// VISUAL TWEAK: Increase for darker dates; decrease for lighter secondary styling.
    static let calendarDayTextOpacityDefault: Double = 0.75

    /// VISUAL TWEAK: Change `calendarDayHighlightOpacity` to adjust the today chip fill strength.
    /// VISUAL TWEAK: Increase for a stronger highlight; decrease for a subtler outline.
    static let calendarDayHighlightOpacity: Double = 0.12

    /// VISUAL TWEAK: Change `glassCardCornerRadiusLarge` to adjust roundness of primary cards.
    /// VISUAL TWEAK: Raise for softer cards; lower for squarer cards across Home/Settings.
    static let glassCardCornerRadiusLarge: CGFloat = 26

    /// VISUAL TWEAK: Change `glassShadowRadiusPrimary` to adjust blur on primary glass cards.
    /// VISUAL TWEAK: Increase for softer depth; decrease for crisper shadows.
    static let glassShadowRadiusPrimary: CGFloat = 18

    /// VISUAL TWEAK: Change `glassContentPadding` to adjust padding inside glass cards.
    /// VISUAL TWEAK: Increase for more whitespace inside cards; decrease for denser content.
    static let glassContentPadding: CGFloat = 20

    /// VISUAL TWEAK: Change `glassBackgroundOpacityLight` to shift translucency in Light Mode.
    /// VISUAL TWEAK: Increase to make glass more opaque; decrease for more background bleed.
    static let glassBackgroundOpacityLight: Double = 0.98

    /// VISUAL TWEAK: Change `glassBackgroundOpacityDark` to shift translucency in Dark Mode.
    /// VISUAL TWEAK: Increase for a more solid dark glass; decrease for lighter lift.
    static let glassBackgroundOpacityDark: Double = 1.0

    /// VISUAL TWEAK: Change `glassStrokeOpacityLight` to strengthen or soften light-mode borders.
    /// VISUAL TWEAK: Raise for sharper outlines; lower for subtler strokes.
    static let glassStrokeOpacityLight: Double = 0.16

    /// VISUAL TWEAK: Change `glassStrokeOpacityDark` to strengthen or soften dark-mode borders.
    /// VISUAL TWEAK: Raise for brighter outlines; lower for subtler strokes.
    static let glassStrokeOpacityDark: Double = 0.2

    /// VISUAL TWEAK: Change `glassInnerStrokeOpacityLight` to adjust inner highlight strength in Light Mode.
    /// VISUAL TWEAK: Increase for brighter edges; decrease for flatter glass.
    static let glassInnerStrokeOpacityLight: Double = 0.25

    /// VISUAL TWEAK: Change `glassInnerStrokeOpacityDark` to adjust inner highlight strength in Dark Mode.
    /// VISUAL TWEAK: Increase for brighter edges; decrease for more muted glass.
    static let glassInnerStrokeOpacityDark: Double = 0.08

    /// VISUAL TWEAK: Change `glassDropShadowOpacityLight` to deepen or soften glass depth in Light Mode.
    /// VISUAL TWEAK: Raise to add depth; lower for flatter surfaces.
    static let glassDropShadowOpacityLight: Double = 0.26

    /// VISUAL TWEAK: Change `glassDropShadowOpacityDark` to deepen or soften glass depth in Dark Mode.
    /// VISUAL TWEAK: Raise to add depth; lower for flatter surfaces.
    static let glassDropShadowOpacityDark: Double = 0.28

    /// VISUAL TWEAK: Change `glassAmbientShadowOpacityLight` to adjust ambient softness in Light Mode.
    /// VISUAL TWEAK: Raise for gentler lift; lower for crisper shadows.
    static let glassAmbientShadowOpacityLight: Double = 0.08

    /// VISUAL TWEAK: Change `glassAmbientShadowOpacityDark` to adjust ambient softness in Dark Mode.
    /// VISUAL TWEAK: Raise for gentler lift; lower for crisper shadows.
    static let glassAmbientShadowOpacityDark: Double = 0.04

    /// VISUAL TWEAK: Change `glassButtonCornerRadius` to adjust pill rounding across CTA buttons.
    /// VISUAL TWEAK: Increase for softer pills; decrease for squarer buttons.
    static let glassButtonCornerRadius: CGFloat = 18

    /// VISUAL TWEAK: Change `glassButtonPressedScale` to adjust press depth for CTA buttons.
    /// VISUAL TWEAK: Lower value makes the press feel deeper; higher keeps it flatter.
    static let glassButtonPressedScale: CGFloat = 0.97

    /// VISUAL TWEAK: Change `glassButtonVerticalPadding` to adjust pill button height.
    /// VISUAL TWEAK: Increase for taller pills; decrease for flatter pills.
    static let glassButtonVerticalPadding: CGFloat = 14

    /// VISUAL TWEAK: Change `glassButtonHorizontalPadding` to adjust pill button width padding.
    /// VISUAL TWEAK: Increase for wider pills; decrease for tighter pills.
    static let glassButtonHorizontalPadding: CGFloat = 18

    /// VISUAL TWEAK: Change `settingsHeaderSpacing` to adjust spacing between close/cancel and title.
    /// VISUAL TWEAK: Increase to separate header items; decrease to pull them together.
    static let settingsHeaderSpacing: CGFloat = 14

    /// VISUAL TWEAK: Change `rowSpacing` to adjust horizontal spacing inside rows.
    /// VISUAL TWEAK: Increase for airier rows; decrease for denser rows.
    static let rowSpacing: CGFloat = 12

    /// VISUAL TWEAK: Change `rowValueSpacing` to adjust spacing between value and chevron.
    /// VISUAL TWEAK: Increase for more breathing room before icons.
    static let rowValueSpacing: CGFloat = 6

    /// VISUAL TWEAK: Change `settingsGroupCornerRadius` to adjust rounding on settings cards.
    /// VISUAL TWEAK: Increase for softer groups; decrease for sharper cards.
    static let settingsGroupCornerRadius: CGFloat = 18

    /// VISUAL TWEAK: Change `settingsGroupPadding` to adjust padding inside settings cards.
    /// VISUAL TWEAK: Increase for more breathing room; decrease to tighten card content.
    static let settingsGroupPadding: CGFloat = 12

    /// VISUAL TWEAK: Change `dropdownCornerRadius` to adjust rounding on dropdown menus.
    /// VISUAL TWEAK: Increase for pillier dropdowns; decrease for sharper menus.
    static let dropdownCornerRadius: CGFloat = 14

    /// VISUAL TWEAK: Change `dropdownRowHorizontalPadding` to adjust side padding inside dropdown rows.
    /// VISUAL TWEAK: Increase for wider dropdown items; decrease for tighter menus.
    static let dropdownRowHorizontalPadding: CGFloat = 10

    /// VISUAL TWEAK: Change `dropdownRowVerticalPadding` to adjust vertical padding inside dropdown rows.
    /// VISUAL TWEAK: Increase for taller dropdown items; decrease to compact them.
    static let dropdownRowVerticalPadding: CGFloat = 6

    /// VISUAL TWEAK: Change `dropdownMenuPadding` to adjust padding around dropdown menus.
    /// VISUAL TWEAK: Increase for more inset; decrease for tighter container fit.
    static let dropdownMenuPadding: CGFloat = 8

    /// VISUAL TWEAK: Change `dropdownRowSpacing` to adjust spacing between dropdown rows.
    /// VISUAL TWEAK: Increase for more breathing room between options.
    static let dropdownRowSpacing: CGFloat = 6

    /// VISUAL TWEAK: Change `dropdownTrailingPadding` to adjust the inset between dropdown content and the trailing edge.
    /// VISUAL TWEAK: Increase to inset menus further; decrease to align them closer to the edge.
    static let dropdownTrailingPadding: CGFloat = 4

    /// VISUAL TWEAK: Change `dropdownRowCornerRadius` to adjust rounding on individual dropdown rows.
    /// VISUAL TWEAK: Increase for softer rows; decrease for sharper menu items.
    static let dropdownRowCornerRadius: CGFloat = 12

    /// VISUAL TWEAK: Change `dropdownRowFillOpacity` to adjust the fill strength on hovered dropdown rows.
    /// VISUAL TWEAK: Increase for stronger row highlights; decrease for subtler fills.
    static let dropdownRowFillOpacity: Double = 0.1

    /// VISUAL TWEAK: Change `dropdownFillOpacity` to adjust the dropdown menu background strength.
    /// VISUAL TWEAK: Increase for more solid menus; decrease for lighter glass.
    static let dropdownFillOpacity: Double = 0.12

    /// VISUAL TWEAK: Change `dropdownStrokeOpacity` to adjust dropdown border visibility.
    /// VISUAL TWEAK: Increase for stronger outlines; decrease for softer borders.
    static let dropdownStrokeOpacity: Double = 0.18

    /// VISUAL TWEAK: Change `headerIconSize` to adjust icon sizing in headers.
    /// VISUAL TWEAK: Increase for more prominent glyphs; decrease for subtler icons.
    static let headerIconSize: CGFloat = 16

    /// VISUAL TWEAK: Change `headerButtonFillOpacityLight` to adjust chip fill strength in Light Mode.
    /// VISUAL TWEAK: Increase for bolder fills; decrease for subtler backgrounds.
    static let headerButtonFillOpacityLight: Double = 0.16

    /// VISUAL TWEAK: Change `headerButtonFillOpacityDark` to adjust chip fill strength in Dark Mode.
    /// VISUAL TWEAK: Increase for bolder fills; decrease for subtler backgrounds.
    static let headerButtonFillOpacityDark: Double = 0.12

    /// VISUAL TWEAK: Change `headerButtonStrokeOpacity` to adjust the outline strength on header chips.
    /// VISUAL TWEAK: Increase for clearer borders; decrease for softer outlines.
    static let headerButtonStrokeOpacity: Double = 0.2

    /// VISUAL TWEAK: Change `shortAnimationDuration` to adjust lightweight fade/move timings.
    /// VISUAL TWEAK: Increase for slower dropdown motions; decrease for snappier transitions.
    static let shortAnimationDuration: Double = 0.15

    /// VISUAL TWEAK: Change `navigationTitleSpacing` to adjust spacing inside workout header block.
    /// VISUAL TWEAK: Increase to separate title and subtitle; decrease to tighten them.
    static let navigationTitleSpacing: CGFloat = 6

    /// VISUAL TWEAK: Change `contentSpacingLarge` to adjust large vertical gaps like between header and button.
    /// VISUAL TWEAK: Increase for more breathing room; decrease for denser stacks.
    static let contentSpacingLarge: CGFloat = 24

    /// VISUAL TWEAK: Change `homeBottomInset` to adjust padding at the bottom of Home's scroll area.
    /// VISUAL TWEAK: Increase to lift content higher above the Start pill; decrease to lower it.
    static let homeBottomInset: CGFloat = 160

    /// VISUAL TWEAK: Change `homeBottomSpacer` to adjust spacer height under the calendar.
    /// VISUAL TWEAK: Increase for more scrollable space; decrease to tighten layout.
    static let homeBottomSpacer: CGFloat = 120

    /// VISUAL TWEAK: Change `settingsBottomPadding` to adjust padding at the bottom of the Settings scroll.
    /// VISUAL TWEAK: Increase for extra breathing room below the last section; decrease to pull it tighter.
    static let settingsBottomPadding: CGFloat = 40

    /// VISUAL TWEAK: Change `startButtonBottomPadding` to move the Start pill up/down from the bottom edge.
    /// VISUAL TWEAK: Increase to lift the pill; decrease to tuck it closer to the safe area.
    static let startButtonBottomPadding: CGFloat = 22

    /// VISUAL TWEAK: Change `startButtonHiddenOffset` to adjust how far the Start pill animates in from below.
    /// VISUAL TWEAK: Increase for a longer travel; decrease for a subtler entrance.
    static let startButtonHiddenOffset: CGFloat = 10

    /// VISUAL TWEAK: Change `dropShadowOffsetY` to adjust the y-offset of glass shadows.
    /// VISUAL TWEAK: Increase for deeper shadows; decrease for flatter shadows.
    static let dropShadowOffsetY: CGFloat = 12

    /// VISUAL TWEAK: Change `dropShadowAmbientRadius` to adjust the blur of ambient shadows.
    /// VISUAL TWEAK: Increase for softer ambient shadows; decrease for crisper edges.
    static let dropShadowAmbientRadius: CGFloat = 4

    /// VISUAL TWEAK: Change `ambientShadowOffsetY` to adjust the vertical offset of ambient shadows.
    /// VISUAL TWEAK: Increase for deeper ambient lift; decrease for flatter presentation.
    static let ambientShadowOffsetY: CGFloat = 2

    /// VISUAL TWEAK: Change `dropdownWidth` to adjust max width for dropdown menus.
    /// VISUAL TWEAK: Increase to fit longer labels; decrease for slimmer menus.
    static let dropdownWidth: CGFloat = 170

    /// VISUAL TWEAK: Change `settingsBackgroundOpacityLight` to adjust the light-mode settings backdrop.
    /// VISUAL TWEAK: Increase for a more opaque base; decrease for lighter translucency.
    static let settingsBackgroundOpacityLight: Double = 0.96

    /// VISUAL TWEAK: Change `settingsBackgroundOpacityDark` to adjust the dark-mode settings backdrop.
    /// VISUAL TWEAK: Increase for a more opaque base; decrease for lighter translucency.
    static let settingsBackgroundOpacityDark: Double = 0.94

    /// VISUAL TWEAK: Change `headerPlaceholderWidth` to adjust the balancing spacer width in headers.
    /// VISUAL TWEAK: Increase to widen symmetry; decrease for tighter header balance.
    static let headerPlaceholderWidth: CGFloat = 40

    /// VISUAL TWEAK: Change `pillImageSize` to adjust icon size inside pills.
    /// VISUAL TWEAK: Increase for bigger icons; decrease for subtler icons.
    static let pillImageSize: CGFloat = 20

    /// VISUAL TWEAK: Change `headerIconHitArea` to adjust hit target padding around header icons.
    /// VISUAL TWEAK: Increase for easier taps; decrease for tighter chips.
    static let headerIconHitArea: CGFloat = 12

    /// VISUAL TWEAK: Change `popupMaxWidth` to constrain small menus/alerts.
    /// VISUAL TWEAK: Lower for tighter popups; raise for wider menus.
    static let popupMaxWidth: CGFloat = 420

    /// VISUAL TWEAK: Change `popupAnimation` to adjust popup show/hide motion globally.
    static let popupAnimation: Animation = .smooth(duration: 0.24)

    private static let helveticaName = "Helvetica Neue"

    static func font(for scale: AppTypeScale, weightOverride: Font.Weight? = nil, italicOverride: Bool? = nil) -> Font {
        let descriptor = descriptor(for: scale)
        let weight = weightOverride ?? descriptor.weight
        let italic = italicOverride ?? descriptor.italic
        let baseFont = Font.custom(helveticaName, size: descriptor.size).weight(weight)
        return italic ? baseFont.italic() : baseFont
    }

    private static func descriptor(for scale: AppTypeScale) -> (size: CGFloat, weight: Font.Weight, italic: Bool) {
        switch scale {
        case .brand:
            return (brandBaseSize + fontBump, brandWeight, brandItalic)
        case .title:
            return (titleBaseSize + fontBump, titleWeight, false)
        case .title3:
            return (title3BaseSize + fontBump, title3Weight, false) // VISUAL TWEAK: Change `title3Size` to tune medium headings globally.
        case .section:
            return (sectionBaseSize + fontBump, sectionWeight, false)
        case .body:
            return (bodyBaseSize + fontBump, bodyWeight, false)
        case .footnote:
            return (footnoteBaseSize + fontBump, footnoteWeight, false) // VISUAL TWEAK: Change `footnoteSize` to tune small helper text globally.
        case .caption:
            return (captionBaseSize + fontBump, captionWeight, false)
        case .pill:
            return (pillBaseSize + fontBump, pillWeight, false)
        }
    }
}

extension View {
    func appFont(_ scale: AppTypeScale, weight: Font.Weight? = nil, italic: Bool? = nil) -> some View {
        font(AppStyle.font(for: scale, weightOverride: weight, italicOverride: italic))
    }
}
