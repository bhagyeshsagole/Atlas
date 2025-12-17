//
//  RoutineListView.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//
//  Update: Hardening pass to align header hit areas, popup sizing, haptics, and truncation.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RoutineListView: View {
    @EnvironmentObject private var routineStore: RoutineStore
    @State private var routineToEdit: Routine?
    @State private var routineMenuTarget: Routine?
    @State private var isMenuPresented = false

    let onAddRoutine: () -> Void

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    if routineStore.routines.isEmpty {
                        Text("No routines yet — tap + to add")
                            .appFont(.body, weight: .regular)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, AppStyle.sectionSpacing)
                    } else {
                        ForEach(routineStore.routines) { routine in
                            RoutineCardView(
                                routine: routine,
                                onStart: { startRoutine(routine) },
                                onMenu: { presentRoutineMenu(for: routine) }
                            )
                        }
                    }
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.vertical, AppStyle.screenTopPadding)
            }
            .scrollIndicators(.hidden)

            if let routine = routineMenuTarget, isMenuPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissRoutineMenu()
                    }
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(spacing: 12) {
                            Button {
                                #if DEBUG
                                print("[ROUTINE] Edit selected: \(routine.name)")
                                #endif
                                Haptics.playLightTap()
                                routineToEdit = routine
                                dismissRoutineMenu()
                            } label: {
                                Text("Edit")
                                    .appFont(.title3, weight: .semibold)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                            }
                            Divider().foregroundStyle(.white.opacity(0.2))
                            Button(role: .destructive) {
                                routineStore.deleteRoutine(id: routine.id)
                                Haptics.playLightTap()
                                #if DEBUG
                                print("[ROUTINE] Delete selected: \(routine.name)")
                                print("[ROUTINE] Total routines now: \(routineStore.routines.count)")
                                #endif
                                dismissRoutineMenu()
                            } label: {
                                Text("Delete")
                                    .appFont(.title3, weight: .semibold)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: AppStyle.popupMaxWidth)
                    Button("Cancel") {
                        dismissRoutineMenu()
                    }
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center) // VISUAL TWEAK: Change popup width/spacing.
                .transition(.opacity)
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onAddRoutine) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold)) // VISUAL TWEAK: Change `plusSize` to make it heavier/lighter.
                        .foregroundStyle(.primary)
                }
                .padding(AppStyle.headerIconHitArea)
                .contentShape(Rectangle())
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
        .animation(AppStyle.popupAnimation, value: isMenuPresented)
    }

    private func startRoutine(_ routine: Routine) {
        Haptics.playLightTap()
        #if DEBUG
        print("[ROUTINE] Start workout tapped: \(routine.name)")
        #endif
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
    let title = routine.name.lowercased()
    let descriptor: String
    if title.contains("pull") || title.contains("back") {
        descriptor = "Back + Biceps"
    } else if title.contains("push") || title.contains("chest") {
        descriptor = "Chest + Triceps"
    } else if title.contains("leg") || title.contains("legs") {
        descriptor = "Legs"
    } else {
        descriptor = "Full Body"
    }
    return "\(count) exercises · \(descriptor)"
}

private func routineTags(_ routine: Routine) -> [String] {
    let title = routine.name.lowercased()
    var tags: [String] = []
    if title.contains("pull") || title.contains("back") { tags.append("Pull") }
    if title.contains("push") || title.contains("chest") { tags.append("Push") }
    if title.contains("leg") || title.contains("legs") { tags.append("Legs") }
    if title.contains("home") { tags.append("Home") }
    if title.contains("strength") { tags.append("Strength") }
    return Array(tags.prefix(3))
}

private struct RoutineCardView: View {
    let routine: Routine
    let onStart: () -> Void
    let onMenu: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(routine.name)
                        .appFont(.title, weight: .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    HStack(spacing: 10) {
                        Text(routineOverviewText(routine))
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Button(action: onMenu) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
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
