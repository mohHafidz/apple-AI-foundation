//
//  CalendarService.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    @Published var exportMessage: String = ""
    @Published var isExportSuccess: Bool = false

    private let eventStore = EKEventStore()

    /// Menyuntikkan semua jadwal pola hidup ke tanggal yang dipilih (default: Besok)
    func exportSchedulesToAppleCalendar(
        _ items: [LifestyleScheduleItem],
        targetDate: Date
    ) async {
        exportMessage = "Meminta izin akses Apple Calendar..."
        isExportSuccess = false

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else {
                exportMessage =
                    "⚠️ Izin Kalender ditolak. Buka System Settings > Privacy & Security > Calendars dan aktifkan AcneCareAI."
                return
            }

            guard let targetCalendar = eventStore.defaultCalendarForNewEvents
            else {
                exportMessage =
                    "⚠️ Tidak menemukan kalender default di Mac Anda."
                return
            }

            let calendar = Calendar.current
            var savedCount = 0

            for item in items {
                let event = EKEvent(eventStore: eventStore)
                event.title =
                    "\(emojiForCategory(item.category)) [AcneCare] \(item.title)"
                event.notes =
                    "Kategori: \(item.category)\nManfaat Kulit: \(item.benefitNotes)\n\nDibuat otomatis oleh AcneCareAI."
                event.calendar = targetCalendar

                var dateComponents = calendar.dateComponents(
                    [.year, .month, .day],
                    from: targetDate
                )
                dateComponents.hour = item.hour
                dateComponents.minute = item.minute

                if let startDate = calendar.date(from: dateComponents) {
                    event.startDate = startDate
                    event.endDate = calendar.date(
                        byAdding: .minute,
                        value: item.durationMinutes,
                        to: startDate
                    )

                    // Pasang pengingat otomatis 10 menit sebelum jam makan/olahraga
                    let alarm = EKAlarm(relativeOffset: -600)
                    event.addAlarm(alarm)

                    try eventStore.save(event, span: .thisEvent)
                    savedCount += 1
                }
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "id_ID")
            formatter.dateStyle = .medium

            isExportSuccess = true
            exportMessage =
                "✅ \(savedCount) jadwal berhasil dimasukkan ke Apple Calendar untuk \(formatter.string(from: targetDate))!"

        } catch {
            isExportSuccess = false
            exportMessage =
                "❌ Gagal menyimpan ke Kalender: \(error.localizedDescription)"
        }
    }

    /// Membuka aplikasi Apple Calendar bawaan macOS secara langsung
    func openAppleCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.iCal"
        ) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    private func emojiForCategory(_ category: String) -> String {
        let lower = category.lowercased()
        if lower.contains("nutrisi") || lower.contains("makan") { return "🥗" }
        if lower.contains("olahraga") { return "🏃‍♂️" }
        if lower.contains("hidrasi") || lower.contains("minum") { return "💧" }
        return "😴"
    }
}
