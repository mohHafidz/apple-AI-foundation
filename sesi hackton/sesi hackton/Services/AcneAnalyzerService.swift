//
//  AcneAnalyzerService.swift
//  sesi hackton
//
//  Created by Antigravity on 16/10/26.
//

import CoreML
import UIKit
import Vision

/// Service untuk menganalisis gambar wajah menggunakan model CoreML `best_yolo_acne`
/// dan menggambar bounding box berwarna sesuai jenis jerawat dengan persentase tertinggi.
final class AcneAnalyzerService {
    static let shared = AcneAnalyzerService()

    private var vnModel: VNCoreMLModel?

    private init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let coreMLModel = try best_yolo_acne(configuration: config).model
            let visionModel = try VNCoreMLModel(for: coreMLModel)
            self.vnModel = visionModel
        } catch {
            print("Gagal memuat model best_yolo_acne: \(error.localizedDescription)")
        }
    }

    /// Analisis ketiga sisi wajah dan kembalikan array `FaceSideScanResult`
    func analyzeAllSides(capturedImages: [FaceSide: UIImage]) async -> [FaceSideScanResult] {
        var results: [FaceSideScanResult] = []
        for side in FaceSide.allCases {
            if let image = capturedImages[side] {
                let result = await analyze(image: image, side: side)
                results.append(result)
            }
        }
        return results
    }

    /// Analisis 1 gambar wajah menggunakan Vision + CoreML
    func analyze(image: UIImage, side: FaceSide) async -> FaceSideScanResult {
        let normalizedImage = image.normalizedUpImage()
        let detections = await detectAcne(in: normalizedImage)
        let annotated = Self.drawBoundingBoxes(on: normalizedImage, detections: detections)
        return FaceSideScanResult(
            side: side,
            originalImage: normalizedImage,
            annotatedImage: annotated,
            detections: detections
        )
    }

    private func detectAcne(in image: UIImage) async -> [AcneDetection] {
        guard let cgImage = image.cgImage else { return [] }
        if vnModel == nil {
            loadModel()
        }
        guard let vnModel = self.vnModel else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, _ in
                guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var detectedItems: [AcneDetection] = []
                for obs in observations {
                    // Urutkan semua kemungkinan klasifikasi dari persentase paling tinggi
                    let sortedLabels = obs.labels.sorted { $0.confidence > $1.confidence }
                    guard let bestLabel = sortedLabels.first else { continue }

                    let candidates = sortedLabels.map {
                        AcneClassCandidate(label: $0.identifier, confidence: $0.confidence)
                    }

                    // Konversi koordinat Vision (origin di kiri-bawah) ke UIKit (origin di kiri-atas)
                    let visionBox = obs.boundingBox
                    let uiKitRect = CGRect(
                        x: visionBox.origin.x,
                        y: 1.0 - visionBox.origin.y - visionBox.height,
                        width: visionBox.width,
                        height: visionBox.height
                    )

                    let topType = AcneType(label: bestLabel.identifier)
                    let detection = AcneDetection(
                        topType: topType,
                        topConfidence: bestLabel.confidence,
                        allCandidates: candidates,
                        normalizedRect: uiKitRect
                    )
                    detectedItems.append(detection)
                }

                // Urutkan dari confidence tertinggi
                detectedItems.sort { $0.topConfidence > $1.topConfidence }
                continuation.resume(returning: detectedItems)
            }

            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("Vision perform error: \(error.localizedDescription)")
                continuation.resume(returning: [])
            }
        }
    }

    /// Menggambar bounding box dengan warna berbeda sesuai jenis jerawat + label persentase tertinggi
    static func drawBoundingBoxes(on image: UIImage, detections: [AcneDetection]) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))

            let cgContext = context.cgContext
            let baseDimension = min(size.width, size.height)
            let strokeWidth = max(3.5, baseDimension * 0.007)
            let fontSize = max(16.0, baseDimension * 0.026)

            for (index, detection) in detections.enumerated() {
                let boxRect = CGRect(
                    x: detection.normalizedRect.origin.x * size.width,
                    y: detection.normalizedRect.origin.y * size.height,
                    width: detection.normalizedRect.width * size.width,
                    height: detection.normalizedRect.height * size.height
                )

                let color = detection.topType.uiColor

                // Fill semi-transparan di dalam bounding box
                cgContext.saveGState()
                cgContext.setFillColor(color.withAlphaComponent(0.18).cgColor)
                let roundedBox = UIBezierPath(roundedRect: boxRect, cornerRadius: strokeWidth * 1.5)
                cgContext.addPath(roundedBox.cgPath)
                cgContext.fillPath()

                // Garis tepi bounding box dengan warna sesuai kelas jerawat
                cgContext.setStrokeColor(color.cgColor)
                cgContext.setLineWidth(strokeWidth)
                cgContext.addPath(roundedBox.cgPath)
                cgContext.strokePath()
                cgContext.restoreGState()

                // Teks label: "#1 whitehead 91%"
                let labelString = "#\(index + 1) \(detection.topType.shortName) \(detection.topPercentageInt)%"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let attributed = NSAttributedString(string: labelString, attributes: attributes)
                let textSize = attributed.size()

                let padX: CGFloat = 8
                let padY: CGFloat = 4
                let badgeWidth = textSize.width + padX * 2
                let badgeHeight = textSize.height + padY * 2

                var badgeX = boxRect.minX
                var badgeY = boxRect.minY - badgeHeight - 2
                if badgeY < 4 {
                    badgeY = boxRect.maxY + 2
                }
                if badgeX + badgeWidth > size.width - 4 {
                    badgeX = max(4, size.width - badgeWidth - 4)
                }

                let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
                let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 6)

                cgContext.saveGState()
                cgContext.setFillColor(color.withAlphaComponent(0.92).cgColor)
                cgContext.addPath(badgePath.cgPath)
                cgContext.fillPath()
                cgContext.restoreGState()

                attributed.draw(at: CGPoint(x: badgeX + padX, y: badgeY + padY))
            }
        }
    }
}

extension UIImage {
    /// Menormalisasi orientasi gambar ke `.up` agar koordinat Vision & UIKit selalu presisi
    func normalizedUpImage() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
