//
//  AcneDetectionModels.swift
//  sesi hackton
//
//  Created by Antigravity on 16/10/26.
//

import SwiftUI
import UIKit

/// Status jarak wajah terhadap kamera berdasarkan ukuran bounding box wajah
enum FaceDistanceStatus: Equatable {
    case noFace
    case tooFar
    case tooClose
    case optimal

    var title: String {
        switch self {
        case .noFace:
            return "Wajah Belum Terdeteksi"
        case .tooFar:
            return "Terlalu Jauh — Dekatkan Wajah"
        case .tooClose:
            return "Terlalu Dekat — Jauhkan Sedikit"
        case .optimal:
            return "Jarak Ideal"
        }
    }

    var systemIcon: String {
        switch self {
        case .noFace:
            return "face.dashed"
        case .tooFar:
            return "arrow.up.left.and.arrow.down.right"
        case .tooClose:
            return "arrow.down.right.and.arrow.up.left"
        case .optimal:
            return "checkmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .noFace:
            return .red
        case .tooFar, .tooClose:
            return .orange
        case .optimal:
            return .green
        }
    }
}

/// Sisi wajah yang dipindai
enum FaceSide: String, CaseIterable, Identifiable {
    case front = "Depan"
    case right = "Samping Kanan"
    case left = "Samping Kiri"

    var id: String { rawValue }

    var instructionTitle: String {
        switch self {
        case .front:
            return "Sisi Depan Wajah"
        case .right:
            return "Sisi Kanan Wajah"
        case .left:
            return "Sisi Kiri Wajah"
        }
    }

    var instructionSubtitle: String {
        switch self {
        case .front:
            return "Hadapkan wajah lurus ke depan lalu tahan tombol untuk memotret"
        case .right:
            return "Tolehkan wajah ke kiri (pipi kanan) lalu tahan tombol untuk memotret"
        case .left:
            return "Tolehkan wajah ke kanan (pipi kiri) lalu tahan tombol untuk memotret"
        }
    }

    var systemIcon: String {
        switch self {
        case .front:
            return "face.smiling"
        case .right:
            return "arrow.turn.up.left"
        case .left:
            return "arrow.turn.up.right"
        }
    }
}

/// Jenis jerawat sesuai label pada best_yolo_acne.mlpackage
enum AcneType: String, CaseIterable, Identifiable {
    case blackhead = "blackhead"
    case nodule = "nodule"
    case papule = "papule"
    case pustule = "pustule"
    case whitehead = "whitehead"
    case unknown = "acne"

    var id: String { rawValue }

    init(label: String) {
        let normalized = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self = AcneType.allCases.first(where: { $0.rawValue == normalized }) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .blackhead: return "Blackhead (Komedo Hitam)"
        case .nodule: return "Nodule (Jerawat Nodul)"
        case .papule: return "Papule (Jerawat Papula)"
        case .pustule: return "Pustule (Jerawat Pustula)"
        case .whitehead: return "Whitehead (Komedo Putih)"
        case .unknown: return "Acne"
        }
    }

    var shortName: String {
        rawValue
    }

    /// Warna khusus untuk setiap jenis jerawat (SwiftUI Color)
    var color: Color {
        switch self {
        case .whitehead:
            return Color(red: 0.05, green: 0.82, blue: 0.95) // Cyan cerah
        case .pustule:
            return Color(red: 1.00, green: 0.60, blue: 0.00) // Oranye terang
        case .papule:
            return Color(red: 1.00, green: 0.23, blue: 0.38) // Merah muda / Coral
        case .nodule:
            return Color(red: 0.72, green: 0.25, blue: 0.98) // Ungu terang
        case .blackhead:
            return Color(red: 0.20, green: 0.88, blue: 0.45) // Hijau zamrud
        case .unknown:
            return .yellow
        }
    }

    /// Warna UIKit untuk menggambar bounding box pada tekstur gambar & 3D
    var uiColor: UIColor {
        switch self {
        case .whitehead:
            return UIColor(red: 0.05, green: 0.82, blue: 0.95, alpha: 1.0)
        case .pustule:
            return UIColor(red: 1.00, green: 0.60, blue: 0.00, alpha: 1.0)
        case .papule:
            return UIColor(red: 1.00, green: 0.23, blue: 0.38, alpha: 1.0)
        case .nodule:
            return UIColor(red: 0.72, green: 0.25, blue: 0.98, alpha: 1.0)
        case .blackhead:
            return UIColor(red: 0.20, green: 0.88, blue: 0.45, alpha: 1.0)
        case .unknown:
            return .systemYellow
        }
    }
}

/// Kandidat klasifikasi untuk 1 objek jerawat (seperti pada gambar: whitehead 91%, pustule 8%)
struct AcneClassCandidate: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let confidence: Float

    var percentageInt: Int {
        Int((confidence * 100).rounded())
    }
}

/// Satu objek jerawat yang terdeteksi pada gambar
struct AcneDetection: Identifiable {
    let id = UUID()
    /// Kategori dengan persentase paling tinggi
    let topType: AcneType
    /// Confidence tertinggi (0.0 - 1.0)
    let topConfidence: Float
    /// Semua kandidat probabilitas dari 1 objek yang diidentifikasi (diurutkan dari tertinggi)
    let allCandidates: [AcneClassCandidate]
    /// Bounding box ternormalisasi dalam koordinat gambar (origin di kiri-atas, 0..1)
    let normalizedRect: CGRect

    var topPercentageInt: Int {
        Int((topConfidence * 100).rounded())
    }
}

/// Hasil scan dan analisis untuk 1 sisi wajah
struct FaceSideScanResult: Identifiable {
    let id = UUID()
    let side: FaceSide
    let originalImage: UIImage
    let annotatedImage: UIImage
    let detections: [AcneDetection]
}
