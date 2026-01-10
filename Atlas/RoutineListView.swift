//
//  RoutineListView.swift
//  Atlas
//
//  What this file is:
//  - Lists saved routines and provides entry points to start, edit, or delete them.
//
//  Where it’s used:
//  - Pushed from `ContentView` when the user taps Start Workout on Home.
//  - Presents edit and pre-start flows for the selected routine.
//
//  Called from:
//  - Navigated to via `ContentView` (Start Workout) and pushes `CreateRoutineView`, `EditRoutineView`, and `RoutinePreStartView`.
//
//  Key concepts:
//  - Uses `@EnvironmentObject` to read `RoutineStore` so changes propagate automatically.
//  - Centered glass menu shows actions for each routine without leaving the list.
//
//  Safe to change:
//  - Copy text, spacing, or which actions appear in the menu.
//
//  NOT safe to change:
//  - Deleting routines without calling `routineStore.save()` through store methods; keep mutations via the store.
//  - Navigation destinations tied to `routineToEdit`/`selectedRoutine`; removing them blocks flows.
//
//  Common bugs / gotchas:
//  - Forgetting to reset `routineMenuTarget` when dismissing leaves stale menus onscreen.
//  - Navigating directly without updating `path` from ContentView can desync the stack.
//
//  DEV MAP:
//  - See: DEV_MAP.md → B) Routines (templates)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RoutineListView: View {
    @EnvironmentObject private var routineStore: RoutineStore
    @State private var routineToEdit: Routine? // Drives navigation into the Edit screen.
    @State private var routineMenuTarget: Routine? // The routine currently showing the action menu.
    @State private var isMenuPresented = false // Controls visibility of the center popup menu.
    @State private var pendingDeleteRoutine: Routine?
    @State private var showDeleteConfirm = false
    @State private var selectedRoutine: Routine? // Drives navigation into the pre-start flow.

    let onAddRoutine: () -> Void

    private var coachRoutines: [Routine] {
        routineStore.routines.filter { $0.isCoachSuggested }
    }

    private var userRoutines: [Routine] {
        routineStore.routines.filter { !$0.isCoachSuggested }
    }

    private var coachSections: [(key: String, value: [Routine])] {
        let grouped = Dictionary(grouping: coachRoutines) { $0.coachGroupLabel ?? "Coach Suggested" }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    if coachRoutines.isEmpty && userRoutines.isEmpty {
                        Text("No routines yet — tap + to add")
                            .appFont(.body, weight: .regular)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, AppStyle.sectionSpacing)
                    } else {
                        if !coachRoutines.isEmpty {
                            Text("Coach Suggested")
                                .appFont(.section, weight: .bold)
                                .foregroundStyle(.primary)
                            ForEach(coachSections, id: \.key) { groupLabel, routines in
                                if !groupLabel.isEmpty {
                                    Text(groupLabel)
                                        .appFont(.footnote, weight: .semibold)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(routines) { routine in
                                    RoutineCardView(
                                        routine: routine,
                                        onStart: { startRoutine(routine) },
                                        onMenu: { presentRoutineMenu(for: routine) }
                                    )
                                }
                            }
                        }

                        if !userRoutines.isEmpty {
                            Text("My Routines")
                                .appFont(.section, weight: .bold)
                                .foregroundStyle(.primary)
                            ForEach(userRoutines) { routine in
                                RoutineCardView(
                                    routine: routine,
                                    onStart: { startRoutine(routine) },
                                    onMenu: { presentRoutineMenu(for: routine) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.vertical, AppStyle.screenTopPadding)
            }
            .scrollIndicators(.hidden)

            if let routine = routineMenuTarget, isMenuPresented {
                GlassActionPopup(
                    title: "Routine options",
                    actions: [
                        .init(title: "Edit", isDestructive: false, action: {
                            routineToEdit = routine
                            dismissRoutineMenu()
                        }),
                        .init(title: "Delete", isDestructive: true, action: {
                            pendingDeleteRoutine = routine
                            showDeleteConfirm = true
                            dismissRoutineMenu()
                        })
                    ],
                    onDismiss: dismissRoutineMenu
                )
            }

            if showDeleteConfirm, let routine = pendingDeleteRoutine {
                GlassConfirmPopup(
                    title: "Delete routine?",
                    message: "This cannot be undone.",
                    primaryTitle: "Delete",
                    secondaryTitle: "Cancel",
                    isDestructive: true,
                    isPresented: $showDeleteConfirm,
                    onPrimary: {
                        routineStore.deleteRoutine(id: routine.id)
                        pendingDeleteRoutine = nil
                    },
                    onSecondary: {
                        pendingDeleteRoutine = nil
                    }
                )
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AtlasHeaderIconButton(systemName: "plus", action: onAddRoutine)
            }
        }
        .tint(.primary)
        .navigationDestination(item: $routineToEdit) { routine in
            EditRoutineView(routine: routine) { updated in
                routineStore.updateRoutine(updated)
                #if DEBUG
                print("[ROUTINE] Total routines now: \(routineStore.routines.count)")
                #endif
            }
        }
        .navigationDestination(item: $selectedRoutine) { routine in
            RoutinePreStartView(routine: routine)
        }
        .animation(AppStyle.popupAnimation, value: isMenuPresented)
    }

    private func startRoutine(_ routine: Routine) {
        Haptics.playLightTap()
        #if DEBUG
        print("[ROUTINE] Start workout tapped: \(routine.name)")
        #endif
        selectedRoutine = routine
    }

    private func presentRoutineMenu(for routine: Routine) {
        if !isMenuPresented {
            #if DEBUG
            print("[ROUTINE] Menu opened for: \(routine.name)")
            #endif
        }
        Haptics.playLightTap()
        routineMenuTarget = routine
        withAnimation(AppStyle.popupAnimation) { isMenuPresented = true }
    }

    private func dismissRoutineMenu() {
        if isMenuPresented {
            #if DEBUG
            print("[ROUTINE] Menu dismissed")
            #endif
        }
        withAnimation(AppStyle.popupAnimation) { isMenuPresented = false }
        routineMenuTarget = nil
    }
}

func routineOverviewText(_ routine: Routine) -> String {
    let count = routine.workouts.count
    let tags = muscleTags(for: routine)
    let descriptor = tags.isEmpty ? "Full Body" : tags.prefix(2).map { $0.rawValue }.joined(separator: " • ")
    return "\(count) exercises · \(descriptor)"
}

private func routineTags(_ routine: Routine) -> [String] {
    var tags: [String] = []
    if routine.isCoachSuggested {
        tags.append("Coach")
    }
    let muscles = muscleTags(for: routine)
    tags.append(contentsOf: muscles.prefix(3).map { $0.rawValue })
    return tags
}

private struct RoutineCardView: View {
    let routine: Routine
    let onStart: () -> Void
    let onMenu: () -> Void

    var body: some View {
        AtlasRowPill {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(routine.name)
                        .appFont(.title, weight: .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if routine.isCoachSuggested {
                        Text("Coach")
                            .appFont(.caption, weight: .bold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Text(routineOverviewText(routine))
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        AtlasHeaderIconButton(systemName: "ellipsis", action: onMenu)
                    }
                }
                let tags = routineTags(routine)
                if !tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.08))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onStart()
        }
    }
}

private struct GlassActionPopup: View {
    struct ActionItem: Identifiable {
        let id = UUID()
        let title: String
        let isDestructive: Bool
        let action: () -> Void
    }

    let title: String
    let actions: [ActionItem]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    Haptics.playLightTap()
                    onDismiss()
                }

            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.primary)
                    ForEach(actions) { item in
                        AtlasPillButton(item.title) {
                            if item.isDestructive {
                                Haptics.playHeavyImpact()
                            } else {
                                Haptics.playLightTap()
                            }
                            item.action()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tint(item.isDestructive ? .red : .primary)
                    }
                    AtlasPillButton("Cancel") {
                        Haptics.playLightTap()
                        onDismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 32)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.18), value: actions.count)
        .zIndex(5)
        .onAppear {
            Haptics.playLightTap()
        }
    }
}

private func muscleTags(for routine: Routine) -> [MuscleGroup] {
    var counts: [MuscleGroup: Int] = [:]
    for workout in routine.workouts {
        let lower = workout.name.lowercased()
        func contains(_ keywords: [String]) -> Bool {
            keywords.contains { lower.contains($0) }
        }
        if contains(["squat", "lunge", "leg press", "rdl", "deadlift", "calf"]) {
            counts[.legs, default: 0] += 1
        }
        if contains(["row", "pulldown", "pull-up", "pullup", "lat", "rear delt"]) {
            counts[.back, default: 0] += 1
        }
        if contains(["bench", "press", "fly"]) {
            counts[.chest, default: 0] += 1
        }
        if contains(["ohp", "shoulder", "overhead", "lateral raise", "face pull"]) {
            counts[.shoulders, default: 0] += 1
        }
        if contains(["curl", "bicep", "tricep", "extension", "pushdown", "dip"]) {
            counts[.arms, default: 0] += 1
        }
        if contains(["plank", "crunch", "ab", "core", "carry"]) {
            counts[.core, default: 0] += 1
        }
    }
    return counts.sorted { $0.value > $1.value }.map { $0.key }
}
