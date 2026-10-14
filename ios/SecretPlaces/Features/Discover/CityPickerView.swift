import SwiftUI

/// Chooses the city Discover is scoped to: nearest by location, or from the list grouped by country.
struct CityPickerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var locating = false
    @State private var locationFailed = false

    private var groups: [(country: Country?, cities: [City])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = env.cities.filter { c in
            q.isEmpty || c.title.lowercased().contains(q) || (env.country(for: c.countryId)?.name.lowercased().contains(q) ?? false)
        }
        return Dictionary(grouping: matching) { $0.countryId ?? "" }
            .map { (country: env.country(for: $0.key), cities: $0.value.sorted { $0.title < $1.title }) }
            .sorted { ($0.country?.name ?? "") < ($1.country?.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            locating = true
                            let ok = await env.selectNearestCity()
                            locating = false
                            if ok { dismiss() } else { locationFailed = true }
                        }
                    } label: {
                        HStack {
                            Label("Use my location", systemImage: "location.fill").foregroundStyle(Theme.accent)
                            Spacer()
                            if locating { ProgressView() }
                        }
                    }
                    .disabled(locating)
                } footer: {
                    if locationFailed {
                        Text("We couldn't find a covered city near you. Pick one below — more cities are on the way.")
                    }
                }

                ForEach(groups, id: \.country?.id) { group in
                    Section {
                        ForEach(group.cities) { city in
                            Button {
                                env.selectCity(city.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(city.title).foregroundStyle(Theme.text)
                                        Text("\(env.placeCounts[city.id] ?? 0) secrets").font(.caption).foregroundStyle(Theme.textMuted)
                                    }
                                    Spacer()
                                    if city.id == env.selectedCityId {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                                    }
                                }
                            }
                            .accessibilityAddTraits(city.id == env.selectedCityId ? .isSelected : [])
                        }
                    } header: {
                        Text("\(group.country?.emojiFlag ?? "") \(group.country?.name ?? "")")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $query, prompt: Text("City or country"))
            .navigationTitle("Choose a city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
