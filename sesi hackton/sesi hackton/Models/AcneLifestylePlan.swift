//
//  AcneLifestylePlan.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - Model Data Aplikasi untuk UI, TTS, dan Kalender
struct AcneLifestylePlan: Codable, Equatable {
    /// 1. Respons Pertama: Penjelasan mendalam pola hidup (Markdown)
    var detailedGuideMarkdown: String

    /// 2. Respons Kedua: Naskah super singkat & santai khusus dibacakan TTS (Malas Baca Gimmick)
    var ttsSummaryScript: String

    /// 3. Respons Ketiga: Daftar jadwal konkret untuk dimasukkan ke Apple Calendar
    var dailySchedules: [LifestyleScheduleItem]
}

struct LifestyleScheduleItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String  // Contoh: "Makan Pepaya & Telur Rebus"
    var category: String  // Contoh: "Nutrisi Sayur & Buah", "Protein Bersih", "Olahraga"
    var hour: Int  // Format 24 jam (misal: 7 untuk 07:00)
    var minute: Int  // Menit (misal: 0 atau 30)
    var durationMinutes: Int  // Durasi kegiatan dalam menit
    var benefitNotes: String  // Alasan ilmiah singkat kenapa kegiatan ini membantu jerawat tersebut
}

// MARK: - Skema @Generable Khusus Apple On-Device Foundation Models
#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable
    struct GenerableAcnePlan {
        @Guide(
            description:
                "Penjelasan lengkap dan terstruktur dalam format Markdown tentang cara mengatasi jerawat yang terdeteksi lewat pola makan (sayur spesifik, buah rendah indeks glikemik, protein), olahraga, hidrasi, dan jam tidur. Jangan sebutkan merek skincare."
        )
        let detailedGuideMarkdown: String

        @Guide(
            description:
                "Rangkuman suara super singkat maksimal 3 kalimat dengan bahasa Indonesia santai sehari-hari (gaya ngobrol akrab) untuk dibacakan langsung via Text-to-Speech."
        )
        let ttsSummaryScript: String

        @Guide(
            description:
                "Daftar 5 jadwal kegiatan harian dari pagi sampai malam berisi menu makan sayur/buah/protein dan olahraga untuk di-export ke aplikasi Kalender."
        )
        let dailySchedules: [GenerableScheduleItem]
    }

    @available(macOS 26.0, *)
    @Generable
    struct GenerableScheduleItem {
        @Guide(
            description:
                "Judul aktivitas konkret, contoh: 'Sarapan Oatmeal, Pisang & Telur Rebus' atau 'Jogging Sore Pembersih Keringat'"
        )
        let title: String

        @Guide(
            description:
                "Kategori aktivitas: pilih antara 'Nutrisi', 'Hidrasi', 'Olahraga', atau 'Istirahat'"
        )
        let category: String

        @Guide(
            description:
                "Jam pelaksanaan dalam angka 24-jam (antara 6 sampai 21)"
        )
        let hour: Int

        @Guide(description: "Menit pelaksanaan (0 atau 30)")
        let minute: Int

        @Guide(description: "Durasi kegiatan dalam menit (antara 15 sampai 60)")
        let durationMinutes: Int

        @Guide(
            description:
                "Penjelasan 1 kalimat kenapa makanan atau olahraga ini menekan peradangan jerawat tersebut"
        )
        let benefitNotes: String
    }
#endif
