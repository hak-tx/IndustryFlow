import SwiftUI

struct IndustryPickerView: View {
    @Binding var selectedProfile: IndustryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Industry Profile")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedProfile) {
                ForEach(IndustryProfile.allProfiles) { profile in
                    Label(profile.name, systemImage: profile.icon)
                        .tag(profile)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

// MARK: - Industry Grid (for Settings/expanded view)

struct IndustryGridView: View {
    @Binding var selectedProfile: IndustryProfile

    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(IndustryProfile.allProfiles) { profile in
                IndustryCard(
                    profile: profile,
                    isSelected: selectedProfile.id == profile.id
                )
                .onTapGesture {
                    selectedProfile = profile
                }
            }
        }
    }
}

struct IndustryCard: View {
    let profile: IndustryProfile
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: profile.icon)
                .font(.title3)
                .frame(height: 24)

            Text(profile.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}
