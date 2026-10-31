import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: PersonStore
    @State private var showingAddSheet = false
    @State private var now = Date()

    // Refresh the displayed date/age once a minute so it stays current
    // if the app is left open across midnight.
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.people.isEmpty {
                emptyStateView
            } else {
                listView
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onReceive(timer) { date in
            now = date
        }
        .sheet(isPresented: $showingAddSheet) {
            AddPersonView(isFirstPerson: store.people.isEmpty)
                .environmentObject(store)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No one added yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add a name and birthdate to start tracking their age in days.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Add Person") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .onAppear {
            // Prompt automatically the very first time there's no one stored.
            if store.people.isEmpty {
                showingAddSheet = true
            }
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.people) { person in
                    PersonRow(person: person, referenceDate: now)
                }
                .onDelete(perform: store.removePeople)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Person", systemImage: "plus")
                }
                .padding()
            }
        }
    }
}

struct PersonRow: View {
    let person: Person
    let referenceDate: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.headline)
                let breakdown = person.ageBreakdown(asOf: referenceDate)
                Text("\(breakdown.years)y \(breakdown.months)m \(breakdown.days)d")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(person.ageInDays(asOf: referenceDate).formatted())")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("days")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct AddPersonView: View {
    @EnvironmentObject var store: PersonStore
    @Environment(\.dismiss) var dismiss

    let isFirstPerson: Bool

    @State private var name: String = ""
    @State private var birthdate: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 20) {
            Text(isFirstPerson ? "Add Your First Person" : "Add Person")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Name", text: $name)
                DatePicker("Birthdate", selection: $birthdate, displayedComponents: .date)
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.addPerson(name: trimmed, birthdate: birthdate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .padding(.top)
        .frame(width: 360, height: 220)
    }
}

#Preview {
    ContentView().environmentObject(PersonStore())
}
