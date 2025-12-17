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
                        Button {
                            print("Selected routine: \(routine.name)")
                        } label: {
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
                        }
                        .buttonStyle(.plain)
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
                        .appFont(.section, weight: .semibold)
                        .padding(10)
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
    }
}
