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
import Foundation
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
    @State private var editingGroupId: String?
    @State private var editingGroupName: String = ""
    @State private var showEditGroupSheet = false
    @State private var showDeleteGroupConfirm = false
    @State private var showAddGroupSheet = false
    @State private var newGroupName: String = ""
    @State private var bannerMessage: String?

    let onAddRoutine: (_ initialGroupId: String?) -> Void

struct RoutineGroup: Identifiable {
    let id: String
    let title: String
    let routines: [Routine]
    let isCoach: Bool
    var count: Int { routines.count }
}

    private var groupedSections: [RoutineGroup] {
        let grouped = Dictionary(grouping: routineStore.routines) { $0.groupId }
        var groupIds = Set(grouped.keys)
        groupIds.formUnion(routineStore.groupDisplayNames.keys)
        groupIds.insert(RoutineStore.defaultUserGroupId)

        let sections: [RoutineGroup] = groupIds.compactMap { key in
            let routines = grouped[key] ?? []
            let isCoach = key == RoutineStore.coachGroupId || routines.first?.isCoachSuggested == true
            if isCoach && (routines.isEmpty || routineStore.hiddenCoachGroup) {
                return nil
            }
            let fallback = isCoach ? "Coach Suggested" : "My Routines"
            let title = key == RoutineStore.coachGroupId ? "Coach Suggested" : routineStore.displayName(forGroupId: key, fallback: fallback)
            return RoutineGroup(id: key, title: title, routines: routines.sorted { $0.createdAt > $1.createdAt }, isCoach: isCoach)
        }

        return sections.sorted { lhs, rhs in
            if lhs.isCoach != rhs.isCoach {
                return lhs.isCoach // coach groups first
            }
            return lhs.title < rhs.title
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Start Workout")
                            .appFont(.title, weight: .bold)
                        Spacer()
                        AtlasHeaderIconButton(systemName: "plus", action: { onAddRoutine(nil) })
                    }
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)

                    if routineStore.hiddenCoachGroup {
                        Button {
                            Haptics.playLightTap()
                            routineStore.showCoachGroup()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "eye")
                                Text("Show Coach Suggested")
                                    .appFont(.body, weight: .semibold)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .atlasGlassCard()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppStyle.screenHorizontalPadding)
                    }

                    Button {
                        Haptics.playLightTap()
                        newGroupName = ""
                        showAddGroupSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Group")
                                .appFont(.body, weight: .semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .atlasGlassCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)

                    VStack(spacing: 14) {
                        if groupedSections.isEmpty {
                            Text("No routines yet — tap + to add")
                                .appFont(.body, weight: .regular)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                        }
                        ForEach(groupedSections, id: \.id) { section in
                            GroupSectionCard(
                                section: section,
                                onStartRoutine: { startRoutine($0) },
                                onShowMenu: { presentRoutineMenu(for: $0) },
                                onEditGroup: { beginGroupEdit(id: section.id, currentName: section.title) },
                                onDeleteGroup: { deleteGroup(id: section.id) },
                                onAddRoutine: { onAddRoutine(section.id) }
                            )
                        }
                    }
                }
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
        .sheet(isPresented: $showEditGroupSheet) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Edit Group Name")
                        .appFont(.title3, weight: .bold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Group name", text: $editingGroupName)
                        .padding(AppStyle.settingsGroupPadding)
                        .atlasGlassCard()
                    Spacer()
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditGroupSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { commitGroupEdit() }.bold()
                    }
                }
                if let id = editingGroupId, id != RoutineStore.coachGroupId, id != RoutineStore.defaultUserGroupId {
                    Divider()
                    Button(role: .destructive) {
                        Haptics.playHeavyImpact()
                        showDeleteGroupConfirm = true
                    } label: {
                        Text("Delete Group")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .atlasGlassCard()
                    }
                }
            }
            .presentationDetents([.medium])
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
        }
        .sheet(isPresented: $showAddGroupSheet) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("New Group")
                        .appFont(.title3, weight: .bold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Group name", text: $newGroupName)
                        .padding(AppStyle.settingsGroupPadding)
                        .atlasGlassCard()
                    Spacer()
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddGroupSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { commitAddGroup() }.bold().disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { EmptyView() } }
        .tint(.primary)
        .atlasBackgroundTheme(.workout)
        .atlasBackground()
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
        .overlay {
            if showDeleteGroupConfirm, let id = editingGroupId {
                GlassConfirmPopup(
                    title: "Delete group?",
                    message: "Routines will move to My Routines.",
                    primaryTitle: "Delete",
                    secondaryTitle: "Cancel",
                    isDestructive: true,
                    isPresented: $showDeleteGroupConfirm,
                    onPrimary: {
                        deleteGroup(id: id)
                        showEditGroupSheet = false
                        editingGroupId = nil
                    },
                    onSecondary: { }
                )
            }
        }
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

    private func beginGroupEdit(id: String, currentName: String) {
        editingGroupId = id
        editingGroupName = currentName
        showEditGroupSheet = true
    }

    private func commitGroupEdit() {
        guard let id = editingGroupId else { return }
        routineStore.setGroupDisplayName(for: id, name: editingGroupName)
        showEditGroupSheet = false
    }

    private func commitAddGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = routineStore.createGroup(named: trimmed)
        showAddGroupSheet = false
    }

    private func deleteGroup(id: String) {
        if id == RoutineStore.coachGroupId {
            routineStore.deleteGroup(id: id)
            bannerMessage = "Coach Suggested hidden. Show it again above."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { bannerMessage = nil }
            return
        }
        routineStore.deleteGroup(id: id)
    }
}

private struct GroupSectionCard: View {
    let section: RoutineListView.RoutineGroup
    let onStartRoutine: (Routine) -> Void
    let onShowMenu: (Routine) -> Void
    let onEditGroup: () -> Void
    let onDeleteGroup: () -> Void
    let onAddRoutine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .appFont(.title3, weight: .bold)
                        .foregroundStyle(.primary)
                    Text("\(section.count) routines")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if section.isCoach == false {
                    Button(action: onAddRoutine) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    if section.isCoach == false && section.id != RoutineStore.defaultUserGroupId {
                        Button("Rename", action: onEditGroup)
                    }
                    if section.id != RoutineStore.defaultUserGroupId {
                        Button("Delete", role: .destructive, action: onDeleteGroup)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .menuOrder(.fixed)
            }

            VStack(spacing: 10) {
                ForEach(section.routines) { routine in
                    RoutineRowCard(
                        routine: routine,
                        onStart: { onStartRoutine(routine) },
                        onMenu: { onShowMenu(routine) }
                    )
                }
            }
        }
        .padding(AppStyle.glassContentPadding)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, AppStyle.screenHorizontalPadding)
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
    return Array(NSOrderedSet(array: tags)) as? [String] ?? tags
}

private struct RoutineRowCard: View {
    let routine: Routine
    let onStart: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(routine.name)
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                AtlasHeaderIconButton(systemName: "ellipsis", action: onMenu)
            }
            Text(routineOverviewText(routine))
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            let tags = routineTags(routine)
            if !tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.08)))
                            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                    }
                }
            }
        }
        .padding(AppStyle.glassContentPadding)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.playLightTap()
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

            VStack {
                Spacer()
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
                    .padding(.vertical, AppStyle.glassContentPadding)
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.bottom, AppStyle.screenTopPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
