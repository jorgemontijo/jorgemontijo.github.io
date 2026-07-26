import Foundation

struct Person: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var birthdate: Date

    /// Days elapsed since birthdate, counting the birth day itself as day 0.
    func ageInDays(asOf referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        let startOfBirth = calendar.startOfDay(for: birthdate)
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let components = calendar.dateComponents([.day], from: startOfBirth, to: startOfToday)
        return components.day ?? 0
    }

    /// Years, months, days breakdown for display.
    func ageBreakdown(asOf referenceDate: Date = Date()) -> (years: Int, months: Int, days: Int) {
        let calendar = Calendar.current
        let startOfBirth = calendar.startOfDay(for: birthdate)
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let components = calendar.dateComponents([.year, .month, .day], from: startOfBirth, to: startOfToday)
        return (components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
