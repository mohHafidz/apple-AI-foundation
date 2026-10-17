//
//  LightningExposureModel.swift
//  sesi hackton
//
//  Created by Moden on 17/10/26.
//

import Foundation

/// Nilai default penanganan foto overexposure (luminance 0 = hitam, 1 = putih)
enum LightingConfig {
    static let brightThreshold: Double = 0.70      // rata-rata di atas ini → digelapin
    static let clippedLumaLevel: Double = 0.96     // piksel di atas ini dianggap "mentok putih"
    static let maxClippedFraction: Double = 0.15   // >15% area mentok → warning foto ulang
    static let targetLuminance: Double = 0.50      // target kecerahan setelah dikoreksi
    static let maxReduceEV: Double = 1.0           // batas maksimal penggelapan
    static let highlightAmount: Float = 0.6        // 1 = tanpa efek, makin kecil makin ditekan
    static let centerCropRatio: CGFloat = 0.6      // ukur area tengah aja (wajah)
}
