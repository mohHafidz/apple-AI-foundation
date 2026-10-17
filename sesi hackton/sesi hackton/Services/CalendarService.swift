//
//  CalendarService.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import Combine
import EventKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

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
            let granted: Bool
            if #available(iOS 17.0, macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }

            guard granted else {
                exportMessage =
                    "⚠️ Izin Kalender ditolak. Buka Pengaturan > Privasi & Keamanan > Kalender dan aktifkan izin aplikasi."
                return
            }

            guard let targetCalendar = eventStore.defaultCalendarForNewEvents
            else {
                exportMessage =
                    "⚠️ Tidak menemukan kalender default di perangkat Anda."
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

                    // Pasang pengingat otomatis 10 menit sebelum jam kegiatan
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

    /// Membuka aplikasi Apple Calendar bawaan secara langsung
    func openAppleCalendarApp() {
        #if canImport(UIKit)
        if let url = URL(string: "calshow:") {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.iCal"
        ) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
        #endif
    }

    private func emojiForCategory(_ category: String) -> String {
        let lower = category.lowercased()
        if lower.contains("nutrisi") || lower.contains("makan") { return "🥗" }
        if lower.contains("olahraga") { return "🏃‍♂️" }
        if lower.contains("hidrasi") || lower.contains("minum") { return "💧" }
        return "😴"
    }
}
