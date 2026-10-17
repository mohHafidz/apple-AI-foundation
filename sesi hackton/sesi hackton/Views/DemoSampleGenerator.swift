//
//  DemoSampleGenerator.swift
//  sesi hackton
//
//  Created by Antigravity on 16/10/26.
//

import UIKit

/// Generator data simulasi 5 area wajah (Pipi Kiri, Pipi Kanan, Dahi, Hidung, dan Mulut)
/// apabila pengguna menguji di Simulator tanpa kamera fisik.
enum DemoSampleGenerator {
    static func makeDemoScanResults() -> [FaceSideScanResult] {
        FaceSide.allCases.map { side in
            let baseImage = renderStylizedFaceImage(for: side)
            let sampleDetections = makeSampleDetections(for: side)
            let annotated = AcneAnalyzerService.drawBoundingBoxes(on: baseImage, detections: sampleDetections)
            return FaceSideScanResult(
                side: side,
                originalImage: baseImage,
                annotatedImage: annotated,
                detections: sampleDetections
            )
        }
    }

    private static func makeSampleDetections(for side: FaceSide) -> [AcneDetection] {
        switch side {
        case .leftCheek:
            return [
                AcneDetection(
                    topType: .nodule,
                    topConfidence: 0.86,
                    allCandidates: [
                        AcneClassCandidate(label: "nodule", confidence: 0.86),
                        AcneClassCandidate(label: "papule", confidence: 0.11),
                        AcneClassCandidate(label: "pustule", confidence: 0.03)
                    ],
                    normalizedRect: CGRect(x: 0.44, y: 0.50, width: 0.16, height: 0.12)
                ),
                AcneDetection(
                    topType: .pustule,
                    topConfidence: 0.79,
                    allCandidates: [
                        AcneClassCandidate(label: "pustule", confidence: 0.79),
                        AcneClassCandidate(label: "whitehead", confidence: 0.15)
                    ],
                    normalizedRect: CGRect(x: 0.30, y: 0.36, width: 0.13, height: 0.10)
                )
            ]
        case .rightCheek:
            return [
                AcneDetection(
                    topType: .papule,
                    topConfidence: 0.89,
                    allCandidates: [
                        AcneClassCandidate(label: "papule", confidence: 0.89),
                        AcneClassCandidate(label: "pustule", confidence: 0.09),
                        AcneClassCandidate(label: "nodule", confidence: 0.02)
                    ],
                    normalizedRect: CGRect(x: 0.35, y: 0.48, width: 0.16, height: 0.12)
                ),
                AcneDetection(
                    topType: .whitehead,
                    topConfidence: 0.93,
                    allCandidates: [
                        AcneClassCandidate(label: "whitehead", confidence: 0.93),
                        AcneClassCandidate(label: "pustule", confidence: 0.06)
                    ],
                    normalizedRect: CGRect(x: 0.52, y: 0.60, width: 0.14, height: 0.10)
                )
            ]
        case .forehead:
            return [
                AcneDetection(
                    topType: .whitehead,
                    topConfidence: 0.91,
                    allCandidates: [
                        AcneClassCandidate(label: "whitehead", confidence: 0.91),
                        AcneClassCandidate(label: "pustule", confidence: 0.08),
                        AcneClassCandidate(label: "papule", confidence: 0.01)
                    ],
                    normalizedRect: CGRect(x: 0.42, y: 0.30, width: 0.14, height: 0.10)
                ),
                AcneDetection(
                    topType: .papule,
                    topConfidence: 0.82,
                    allCandidates: [
                        AcneClassCandidate(label: "papule", confidence: 0.82),
                        AcneClassCandidate(label: "whitehead", confidence: 0.14)
                    ],
                    normalizedRect: CGRect(x: 0.28, y: 0.44, width: 0.13, height: 0.10)
                )
            ]
        case .nose:
            return [
                AcneDetection(
                    topType: .blackhead,
                    topConfidence: 0.92,
                    allCandidates: [
                        AcneClassCandidate(label: "blackhead", confidence: 0.92),
                        AcneClassCandidate(label: "whitehead", confidence: 0.07)
                    ],
                    normalizedRect: CGRect(x: 0.44, y: 0.48, width: 0.12, height: 0.10)
                ),
                AcneDetection(
                    topType: .blackhead,
                    topConfidence: 0.81,
                    allCandidates: [
                        AcneClassCandidate(label: "blackhead", confidence: 0.81),
                        AcneClassCandidate(label: "whitehead", confidence: 0.16)
                    ],
                    normalizedRect: CGRect(x: 0.36, y: 0.56, width: 0.11, height: 0.09)
                )
            ]
        case .mouth:
            return [
                AcneDetection(
                    topType: .pustule,
                    topConfidence: 0.87,
                    allCandidates: [
                        AcneClassCandidate(label: "pustule", confidence: 0.87),
                        AcneClassCandidate(label: "papule", confidence: 0.10),
                        AcneClassCandidate(label: "whitehead", confidence: 0.03)
                    ],
                    normalizedRect: CGRect(x: 0.40, y: 0.62, width: 0.15, height: 0.11)
                )
            ]
        }
    }

    static func renderStylizedFaceImage(for side: FaceSide) -> UIImage {
        let size = CGSize(width: 720, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Background gelap lembut
            UIColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Siluet oval kulit wajah close-up
            let faceRect = CGRect(x: 80, y: 90, width: 560, height: 730)
            let facePath = UIBezierPath(ovalIn: faceRect)
            UIColor(red: 0.93, green: 0.78, blue: 0.68, alpha: 1.0).setFill()
            facePath.fill()

            // Shading lembut di tepi wajah
            UIColor(red: 0.84, green: 0.66, blue: 0.56, alpha: 0.55).setStroke()
            facePath.lineWidth = 14
            facePath.stroke()

            // Elemen wajah sederhana sesuai fokus area
            let offsetX: CGFloat
            let offsetY: CGFloat
            switch side {
            case .leftCheek:
                offsetX = -95
                offsetY = 0
            case .rightCheek:
                offsetX = 95
                offsetY = 0
            case .forehead:
                offsetX = 0
                offsetY = 110
            case .nose:
                offsetX = 0
                offsetY = 0
            case .mouth:
                offsetX = 0
                offsetY = -95
            }

            UIColor(red: 0.25, green: 0.18, blue: 0.15, alpha: 0.75).setFill()
            let leftEye = UIBezierPath(ovalIn: CGRect(x: 240 + offsetX, y: 360 + offsetY, width: 65, height: 28))
            let rightEye = UIBezierPath(ovalIn: CGRect(x: 415 + offsetX, y: 360 + offsetY, width: 65, height: 28))
            leftEye.fill()
            rightEye.fill()

            // Hidung
            let nosePath = UIBezierPath(roundedRect: CGRect(x: 342 + offsetX, y: 400 + offsetY, width: 36, height: 110), cornerRadius: 18)
            UIColor(red: 0.85, green: 0.67, blue: 0.57, alpha: 0.85).setFill()
            nosePath.fill()

            // Bibir
            let mouthPath = UIBezierPath(roundedRect: CGRect(x: 295 + offsetX, y: 565 + offsetY, width: 130, height: 34), cornerRadius: 17)
            UIColor(red: 0.82, green: 0.45, blue: 0.48, alpha: 0.85).setFill()
            mouthPath.fill()

            // Titik kemerahan simulasi jerawat di kulit
            let spots: [(CGRect, UIColor)] = [
                (CGRect(x: 335, y: 275, width: 28, height: 28), UIColor(red: 0.95, green: 0.88, blue: 0.85, alpha: 0.9)),
                (CGRect(x: 255, y: 495, width: 32, height: 32), UIColor(red: 0.92, green: 0.35, blue: 0.38, alpha: 0.85)),
                (CGRect(x: 410, y: 485, width: 34, height: 34), UIColor(red: 0.88, green: 0.30, blue: 0.35, alpha: 0.85))
            ]
            for (spotRect, spotColor) in spots {
                spotColor.setFill()
                UIBezierPath(ovalIn: spotRect).fill()
            }

            // Label watermark area wajah
            let title = "AREA: \(side.rawValue.uppercased())"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.75)
            ]
            let attrStr = NSAttributedString(string: title, attributes: attrs)
            let strSize = attrStr.size()
            attrStr.draw(at: CGPoint(x: (size.width - strSize.width) / 2, y: 42))
        }
    }
}
