import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: PersonStore
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People")
                .font(.headline)
                .padding(.top, 12)
                .padding(.horizontal)

            if store.people.isEmpty {
                Text("No one added yet.")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                List {
                    ForEach(store.people) { person in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(person.name)
                                Text(person.birthdate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete(perform: store.removePeople)
                }
            }

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
        .frame(width: 380, height: 320)
        .sheet(isPresented: $showingAddSheet) {
            AddPersonView(isFirstPerson: store.people.isEmpty)
                .environmentObject(store)
        }
    }
}

#Preview {
    SettingsView().environmentObject(PersonStore())
}
