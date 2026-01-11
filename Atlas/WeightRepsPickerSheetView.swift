import SwiftUI

struct WeightRepsPickerSheetView: View {
    @Binding var weightInt: Int
    @Binding var weightDec: Int
    @Binding var reps: Int
    var onChange: () -> Void
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Set Entry")
                    .appFont(.title3, weight: .bold)
                Spacer()
                Button("Log") {
                    onDone()
                    dismiss()
                }
                .buttonStyle(.plain)
                .appFont(.body, weight: .semibold)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("Weight (kg)")
                    .appFont(.section, weight: .bold)
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    picker(for: $weightInt, range: 0...300)
                    Text(".")
                        .appFont(.title, weight: .bold)
                        .frame(width: 12)
                    picker(for: $weightDec, range: 0...9)
                }
                .frame(maxHeight: 180)

                Text("Reps")
                    .appFont(.section, weight: .bold)
                    .foregroundStyle(.secondary)
                picker(for: $reps, range: 0...50)
                    .frame(maxHeight: 180)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 12)
    }

    private func picker(for binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker("", selection: Binding<Int>(
            get: { binding.wrappedValue },
            set: {
                if binding.wrappedValue != $0 {
                    binding.wrappedValue = $0
                    onChange()
                }
            })
        ) {
            ForEach(range, id: \.self) { value in
                Text("\(value)")
                    .appFont(.title, weight: .bold)
                    .foregroundStyle(.primary)
            }
        }
        .pickerStyle(.wheel)
    }
}
