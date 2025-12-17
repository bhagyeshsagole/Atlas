//
//  RoutineListView.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//

import SwiftUI

struct RoutineListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var routineStore: RoutineStore
    @State private var routineToEdit: Routine?
    @State private var routineToDelete: Routine?

    let onAddRoutine: () -> Void

    private let plusButtonSize: CGFloat = 36 // VISUAL TWEAK: Change `plusButtonSize` to adjust the tap target without changing style.
    private let plusIconSize: CGFloat = 16 // VISUAL TWEAK: Change `plusIconSize` to make the + feel lighter/heavier.

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
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { // VISUAL TWEAK: Set `allowsFullSwipe` true/false to control “Mail-like” full swipe.
                            Button("Edit") {
                                routineToEdit = routine
                            }
                            .tint(.gray)

                            Button(role: .destructive) {
                                routineToDelete = routine
                            } label: {
                                Text("Delete")
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
                Button(action: onAddRoutine) {
                    Image(systemName: "plus")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: plusIconSize, weight: .semibold))
                        .frame(width: plusButtonSize, height: plusButtonSize, alignment: .center)
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                                .fill(.white.opacity(colorScheme == .dark ? AppStyle.headerButtonFillOpacityDark : AppStyle.headerButtonFillOpacityLight))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                                .stroke(.white.opacity(AppStyle.headerButtonStrokeOpacity), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .tint(.primary)
            }
        }
        .tint(.primary)
        .confirmationDialog("Delete routine?", isPresented: Binding(get: { routineToDelete != nil }, set: { isPresented in
            if !isPresented { routineToDelete = nil }
        }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let routineToDelete {
                    routineStore.deleteRoutine(id: routineToDelete.id)
                    self.routineToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                routineToDelete = nil
            }
        }
        .navigationDestination(item: $routineToEdit) { routine in
            EditRoutineView(routine: routine) { updated in
                routineStore.updateRoutine(updated)
            }
        }
    }
}
