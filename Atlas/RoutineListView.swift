//
//  RoutineListView.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RoutineListView: View {
    @EnvironmentObject private var routineStore: RoutineStore
    @State private var routineToEdit: Routine?
    @State private var routineMenuTarget: Routine?

    let onAddRoutine: () -> Void

    var body: some View {
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
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(routine.name)
                                    .appFont(.title, weight: .semibold)
                                    .foregroundStyle(.primary)

                                if !routine.workouts.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(routine.workouts) { workout in
                                            Text(workout.name)
                                                .appFont(.body, weight: .medium)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onRoutineTap(routine)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppStyle.screenHorizontalPadding)
            .padding(.vertical, AppStyle.screenTopPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AddButton(action: onAddRoutine)
            }
        }
        .tint(.primary)
        .confirmationDialog("Routine options", isPresented: Binding(get: { routineMenuTarget != nil }, set: { isPresented in
            if !isPresented { routineMenuTarget = nil }
        }), titleVisibility: .visible) { // VISUAL TWEAK: Change pop-up width/padding to make it tighter/looser.
            if let routine = routineMenuTarget {
                Button("Edit") {
                    #if DEBUG
                    print("[ROUTINE] Edit selected: \(routine.name)")
                    #endif
                    routineToEdit = routine
                    routineMenuTarget = nil
                }

                Button("Delete", role: .destructive) {
                    #if DEBUG
                    print("[ROUTINE] Delete selected: \(routine.name)")
                    #endif
                    routineStore.deleteRoutine(id: routine.id)
                    #if DEBUG
                    print("[ROUTINE] Total routines now: \(routineStore.routines.count)")
                    #endif
                    routineMenuTarget = nil
                }
            }
            Button("Cancel", role: .cancel) {
                routineMenuTarget = nil
            }
        }
        .navigationDestination(item: $routineToEdit) { routine in
            EditRoutineView(routine: routine) { updated in
                routineStore.updateRoutine(updated)
                #if DEBUG
                print("[ROUTINE] Total routines now: \(routineStore.routines.count)")
                #endif
            }
        }
    }

    private func onRoutineTap(_ routine: Routine) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred() // VISUAL TWEAK: Change haptic type in `onRoutineTap()` to adjust feedback.
        #endif
        routineMenuTarget = routine
    }
}
