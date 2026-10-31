import Foundation
import Combine
import SwiftUI

final class PersonStore: ObservableObject {
    @Published var people: [Person] = [] {
        didSet { save() }
    }

    private let storageKey = "AgeTracker.people"

    init() {
        load()
    }

    func addPerson(name: String, birthdate: Date) {
        let person = Person(name: name, birthdate: birthdate)
        people.append(person)
    }

    func removePerson(_ person: Person) {
        people.removeAll { $0.id == person.id }
    }

    func removePeople(at offsets: IndexSet) {
        people.remove(atOffsets: offsets)
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Person].self, from: data) else {
            people = []
            return
        }
        people = decoded
    }
}
