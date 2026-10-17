//
//  AcneDetectionInput.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import Foundation

/// Struktur data hasil tangkapan kamera Object Detection teman Anda
struct DetectedAcneItem: Identifiable, Hashable {
    let id = UUID()
    let acneType: String  // Contoh: "Pustula (Jerawat Meradang)", "Komedo Hitam", "Papula"
    let facialArea: String  // Contoh: "Pipi Kanan", "Dahi", "Dagu"
    let count: Int  // Jumlah titik jerawat yang terdeteksi
    let confidence: Double  // Akurasi bounding box (0.0 - 1.0)
}

/// Preset simulasi untuk mengetes aplikasi sebelum model CV teman Anda digabungkan
struct AcneDetectionMockData {
    static let samplePresets: [String: [DetectedAcneItem]] = [
        "Kasus 1: Jerawat Meradang (Pustula & Papula)": [
            DetectedAcneItem(
                acneType: "Pustula (Bernanah Ringan)",
                facialArea: "Pipi Kanan & Kiri",
                count: 4,
                confidence: 0.92
            ),
            DetectedAcneItem(
                acneType: "Papula (Merah Meradang)",
                facialArea: "Garis Rahang / Dagu",
                count: 3,
                confidence: 0.88
            ),
        ],
        "Kasus 2: Komedo & Pori Tersumbat (Whitehead/Blackhead)": [
            DetectedAcneItem(
                acneType: "Blackhead (Komedo Terbuka)",
                facialArea: "Hidung & T-Zone",
                count: 8,
                confidence: 0.95
            ),
            DetectedAcneItem(
                acneType: "Whitehead (Komedo Tertutup)",
                facialArea: "Dahi",
                count: 5,
                confidence: 0.86
            ),
        ],
        "Kasus 3: Jerawat Hormonal & Stres (Nodul Dalam)": [
            DetectedAcneItem(
                acneType: "Nodul (Jerawat Batu Mendalam)",
                facialArea: "Dagu Bawah",
                count: 2,
                confidence: 0.90
            ),
            DetectedAcneItem(
                acneType: "Pustula",
                facialArea: "Pelipis",
                count: 2,
                confidence: 0.84
            ),
        ],
    ]
}
