//
//  FoundationLLMService.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import Combine
import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

@MainActor
final class FoundationLLMService: ObservableObject {
    @Published var currentPlan: AcneLifestylePlan?
    @Published var isGenerating: Bool = false
    @Published var statusLog: String = "Siap menerima data deteksi jerawat."

    /// Fungsi utama: 1x Inference menghasilkan 3 komponen sekaligus
    func generateCompletePlan(from detections: [DetectedAcneItem]) async {
        isGenerating = true
        statusLog = "Mengirim hasil deteksi ke On-Device Foundation Model..."

        let summaryInput = detections.map {
            "\($0.count) \($0.acneType) di area \($0.facialArea)"
        }.joined(separator: ", ")

        let systemPrompt = """
            Kamu adalah ahli dermatologi nutrisi dan gaya hidup holistik di Indonesia.
            Tugasmu memberikan solusi penyembuhan jerawat HANYA melalui perbaikan pola hidup harian:
            1. Asupan sayur hijau, buah tinggi antioksidan, dan sumber protein bersih (rendah gula & bebas susu/dairy).
            2. Aktivitas olahraga terukur untuk menurunkan hormon kortisol dan melancarkan sirkulasi kulit.
            3. Manajemen hidrasi dan tidur berkualitas.
            DILARANG menyarankan produk skincare, krim, atau obat kimia. Gunakan Bahasa Indonesia yang menarik dan aplikatif.
            """

        let userPrompt = """
            Kamera mendeteksi kondisi kulit wajah pengguna sebagai berikut: \(summaryInput).
            Buatkan:
            1. Penjelasan lengkap pola hidup (Markdown).
            2. Rangkuman santai 2-3 kalimat untuk dibacakan oleh suara TTS karena pengguna malas membaca teks panjang.
            3. Jadwal harian konkret dari pagi hingga malam (makan sayur apa, buah apa, protein apa, dan olahraga apa) untuk dimasukkan ke Apple Calendar besok.
            """

        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                do {
                    let session = LanguageModelSession(
                        instructions: systemPrompt
                    )
                    let response = try await session.respond(
                        to: userPrompt,
                        generating: GenerableAcnePlan.self
                    )

                    let generated = response.content
                    let mappedSchedules = generated.dailySchedules.map { item in
                        LifestyleScheduleItem(
                            title: item.title,
                            category: item.category,
                            hour: max(5, min(22, item.hour)),
                            minute: item.minute == 30 ? 30 : 0,
                            durationMinutes: max(15, item.durationMinutes),
                            benefitNotes: item.benefitNotes
                        )
                    }

                    self.currentPlan = AcneLifestylePlan(
                        detailedGuideMarkdown: generated.detailedGuideMarkdown,
                        ttsSummaryScript: generated.ttsSummaryScript,
                        dailySchedules: mappedSchedules
                    )

                    self.statusLog =
                        "Berhasil di-generate oleh Apple On-Device Foundation Model."
                    self.isGenerating = false
                    return
                } catch {
                    print(
                        "FoundationModels fallback aktif karena: \(error.localizedDescription)"
                    )
                }
            }
        #endif

        // Fallback apabila model lokal sedang tidak tersedia / testing UI
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        self.currentPlan = createContextualFallbackPlan(
            summaryInput: summaryInput
        )
        self.statusLog =
            "Berhasil menyusun rencana pola hidup untuk: \(summaryInput)"
        self.isGenerating = false
    }

    /// Fallback dinamis yang menyesuaikan dengan input jerawat yang terdeteksi
    private func createContextualFallbackPlan(summaryInput: String)
        -> AcneLifestylePlan
    {
        let markdown = """
            ### Analisis Pola Hidup untuk Kondisi: \(summaryInput)

            Jerawat yang terdeteksi di area wajah Anda sangat berkaitan erat dengan **lonjakan insulin (gula darah)**, **peradangan sistemik**, dan **tumpukan hormon kortisol**. Tanpa menggunakan produk kimia, berikut adalah protokol pemulihan dari dalam tubuh:

            ---

            #### 1. Protokol Nutrisi Anti-Inflamasi (Sayur, Buah & Protein)
            * **Sayuran Hijau Kaya Zinc & Klorofil:** Konsumsi **Bayam Rebus, Brokoli Kukus, dan Pakcoy** setiap makan siang dan malam. Serat mengikat kelebihan lemak dan toksin di saluran cerna agar tidak memicu sebum berlebih di wajah.
            * **Buah Rendah Glikemik & Tinggi Enzim:** Pilih **Pepaya, Alpukat, Jambu Biji Merah, atau Apel**. Pepaya mengandung enzim *papain* yang meredakan kemerahan dari dalam, sementara alpukat menstabilkan membran sel kulit.
            * **Sumber Protein Bersih (Omega-3 & Non-Dairy):** Ganti gorengan dan olahan susu sapi dengan **Ikan Kembung/Salmon Panggang, Dada Ayam Rebus, Telur Rebus, dan Tempe Kukus**. Ikan kembung kaya akan Omega-3 yang langsung menekan peradangan pustula/nodul.

            ---

            #### 2. Olahraga & Sirkulasi Oksigen Kulit
            * Lakukan **Cardio Ringan (Jogging cepat atau Skipping) selama 25–30 menit** pada sore hari.
            * Keringat sehat membantu membilas pori-pori dari dalam dan menurunkan kadar stres (*kortisol*). **Penting:** Segera bilas wajah dengan air bersih maksimal 10 menit setelah selesai olahraga.

            ---

            #### 3. Hidrasi & Jam Biologis Pemulihan Kulit
            * Minum minimal **2.5 liter air putih** sehari (tambahkan irisan lemon atau timun tanpa gula).
            * Tidur sebelum pukul **22:00 malam**. Regenerasi kolagen dan penurunan kelenjar minyak alami terjadi paling optimal antara pukul 23:00 hingga 02:00 dini hari.
            """

        let ttsScript =
            "Halo! Dari hasil deteksi tadi, ada kondisi \(summaryInput) yang lagi aktif nih. Malas baca penjelasan panjang di sebelah? Tenang, intinya mulai besok kamu cukup kurangi gula dan gorengan, perbanyak makan sayur bayam, buah pepaya, plus protein kayak telur rebus dan ikan. Jangan lupa sorenya olahraga ringan dua puluh lima menit dan tidur sebelum jam sepuluh malam ya. Jadwal lengkapnya udah aku siapin di kanan, tinggal klik satu tombol buat masukin ke kalendermu!"

        let schedules: [LifestyleScheduleItem] = [
            LifestyleScheduleItem(
                title: "Minum Air Hangat + Sarapan 2 Telur Rebus & Pepaya",
                category: "Nutrisi",
                hour: 7,
                minute: 0,
                durationMinutes: 30,
                benefitNotes:
                    "Protein telur mempercepat perbaikan jaringan kulit, sedangkan enzim pepaya melancarkan pencernaan pemicu jerawat."
            ),
            LifestyleScheduleItem(
                title:
                    "Makan Siang: Ikan Kembung/Ayam Kukus + Sayur Bayam & Brokoli",
                category: "Nutrisi",
                hour: 12,
                minute: 30,
                durationMinutes: 45,
                benefitNotes:
                    "Kaya Omega-3 dan Zinc alami untuk mengempiskan jerawat meradang tanpa menaikkan gula darah."
            ),
            LifestyleScheduleItem(
                title:
                    "Cemilan Sore: Potongan Alpukat / Apel & Air Putih 500ml",
                category: "Hidrasi",
                hour: 15,
                minute: 30,
                durationMinutes: 20,
                benefitNotes:
                    "Menjaga kelembapan alami kulit dan menghindari ngemil manis/tepung di sore hari."
            ),
            LifestyleScheduleItem(
                title: "Olahraga Sore: Jogging Santai / Cardio 25 Menit",
                category: "Olahraga",
                hour: 17,
                minute: 0,
                durationMinutes: 30,
                benefitNotes:
                    "Menurunkan hormon stres kortisol penyebab jerawat batu dan membuka sirkulasi oksigen ke pori-pori."
            ),
            LifestyleScheduleItem(
                title:
                    "Makan Malam Bersih: Tempe/Tahu Kukus + Tumis Pakcoy Bawang Putih",
                category: "Nutrisi",
                hour: 19,
                minute: 0,
                durationMinutes: 30,
                benefitNotes:
                    "Probiotik dari tempe dan allicin pada bawang putih membantu menekan bakteri pemicu jerawat dari dalam."
            ),
            LifestyleScheduleItem(
                title: "Matikan Layar & Tidur Malam (Fase Regenerasi Kulit)",
                category: "Istirahat",
                hour: 21,
                minute: 30,
                durationMinutes: 30,
                benefitNotes:
                    "Menekan produksi minyak (sebum) berlebih dan mempercepat pemulihan radang jerawat saat tidur."
            ),
        ]

        return AcneLifestylePlan(
            detailedGuideMarkdown: markdown,
            ttsSummaryScript: ttsScript,
            dailySchedules: schedules
        )
    }
}
