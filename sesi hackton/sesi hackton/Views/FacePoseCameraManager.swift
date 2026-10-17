//
//  FacePoseCameraManager.swift
//  sesi hackton
//
//  Created by Antigravity on 16/10/26.
//

import AVFoundation
import CoreMedia
import Observation
import SwiftUI
import UIKit
import Vision

/// Manager kamera depan dengan 1 metode pengambilan gambar:
/// Pengguna menahan (hold) 1 tombol sembari sistem mengecek apakah jarak wajah
/// tidak terlalu dekat dan tidak terlalu jauh (`FaceDistanceStatus`).
@Observable
final class FacePoseCameraManager: NSObject {
    let session = AVCaptureSession()

    /// Sisi wajah yang sedang diminta untuk di-scan
    var currentTargetSide: FaceSide = .front
    /// Gambar yang sudah berhasil dijepret untuk tiap sisi wajah
    var capturedImages: [FaceSide: UIImage] = [:]
    /// Apakah seluruh 3 sisi wajah sudah selesai dijepret
    var isAllCaptured: Bool {
        FaceSide.allCases.allSatisfy { capturedImages[$0] != nil }
    }

    /// Status kamera & izin
    var isCameraAuthorized: Bool = false
    var isSessionRunning: Bool = false
    var cameraErrorMessage: String?

    /// Apakah efek video bawaan Control Center iOS (Portrait / Studio Light / Pengganti Latar) masih aktif
    var activeSystemEffectsDescription: String?

    /// Indikator deteksi jarak wajah real-time
    var distanceStatus: FaceDistanceStatus = .noFace
    /// Persentase ukuran wajah di layar (untuk umpan balik visual)
    var faceSizeRatio: Double = 0.0

    /// State saat tombol sedang ditahan (hold) oleh pengguna
    var isHoldingCaptureButton: Bool = false
    /// Progress penahanan tombol saat jarak wajah sudah ideal (0.0 ... 1.0)
    var holdProgress: Double = 0.0
    /// Efek flash saat memotret
    var showCaptureFlash: Bool = false

    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.sesihackton.camera.videoQueue", qos: .userInteractive)
    nonisolated private static let rawCIContext: CIContext = {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CIContext(options: [
            .workingColorSpace: sRGB,
            .outputColorSpace: sRGB,
            .cacheIntermediates: false
        ])
    }()

    // State internal yang diakses di videoQueue (nonisolated)
    @ObservationIgnored nonisolated(unsafe) private var latestSampleBufferImage: UIImage?
    @ObservationIgnored nonisolated(unsafe) private var isProcessingFrame: Bool = false
    @ObservationIgnored nonisolated(unsafe) private var isHoldingSnapshot: Bool = false
    @ObservationIgnored nonisolated(unsafe) private var isCooldownActive: Bool = false
    @ObservationIgnored nonisolated(unsafe) private var validHoldFrameCount: Int = 0
    private let requiredHoldFrames: Int = 12 // ~0.5 - 0.6 detik ditahan pada jarak ideal

    // Batas rasio ukuran wajah terhadap frame (tidak terlalu jauh & tidak terlalu dekat)
    private let minOptimalFaceDimension: CGFloat = 0.34
    private let maxOptimalFaceDimension: CGFloat = 0.72

    func checkPermissionAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isCameraAuthorized = true
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isCameraAuthorized = granted
                    if granted {
                        self.configureAndStartSession()
                    } else {
                        self.cameraErrorMessage = "Izin kamera ditolak. Aktifkan izin kamera di Pengaturan atau gunakan Mode Demo 3D."
                    }
                }
            }
        default:
            isCameraAuthorized = false
            cameraErrorMessage = "Akses kamera tidak tersedia pada perangkat ini."
        }
    }

    private func configureAndStartSession() {
        guard !isSessionRunning else { return }

        videoQueue.async { [weak self] in
            guard let self else { return }

            // 1. Paksa Center Stage di bawah kendali aplikasi dan matikan sepenuhnya
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false

            self.session.beginConfiguration()
            // Gunakan .inputPriority dan matikan Wide Color otomatis agar iOS tidak
            // mengganti format ke pipeline Smart HDR / Deep Fusion / P3 Wide Gamut
            self.session.sessionPreset = .inputPriority
            self.session.automaticallyConfiguresCaptureDeviceForWideColor = false

            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }

            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video)

            guard let cameraDevice = device,
                  let input = try? AVCaptureDeviceInput(device: cameraDevice),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.cameraErrorMessage = "Kamera tidak ditemukan pada perangkat ini."
                }
                return
            }

            // Hindari auto-exposure default bawaan preset yang memodifikasi kecerahan
            input.unifiedAutoExposureDefaultsEnabled = false
            self.session.addInput(input)

            // Nonaktifkan efek Cinematic Video (blur/depth sintetis) bila didukung
            if input.isCinematicVideoCaptureSupported {
                input.isCinematicVideoCaptureEnabled = false
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if cameraDevice.position == .front, connection.isVideoMirrored != true, connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
                // Matikan stabilisasi video agar frame tidak mengalami resampling/penghalusan piksel
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .off
                }
            }

            // Pilih format kamera mentah/natural dan matikan seluruh efek pemrosesan perangkat
            self.configureUnprocessedCameraHardware(for: cameraDevice)

            self.session.commitConfiguration()

            // Pastikan kembali konfigurasi tidak ter-reset setelah commitConfiguration()
            self.configureUnprocessedCameraHardware(for: cameraDevice)
            self.session.startRunning()

            let activeEffects = self.detectActiveControlCenterEffects(for: cameraDevice)
            Task { @MainActor in
                self.isSessionRunning = true
                self.activeSystemEffectsDescription = activeEffects
            }
        }
    }

    /// Memilih format sensor yang mendukung Global Tone Mapping & bebas efek, serta mematikan:
    /// - Center Stage
    /// - Auto-HDR & Video HDR (Smart HDR)
    /// - Local Tone Mapping & Multi-frame Fusion (mengaktifkan Global Tone Mapping)
    /// - Face-Driven Auto Exposure & Face-Driven Auto Focus (agar kulit wajah tidak dicerahkan/dihaluskan otomatis)
    /// - Geometric Distortion Correction (agar piksel tidak di-upscale/warping)
    /// - Low-Light Boost & Auto Video Frame Rate (agar tidak ada temporal noise smoothing)
    /// - Wide Color P3 (mengunci ke sRGB standar)
    nonisolated private func configureUnprocessedCameraHardware(for device: AVCaptureDevice) {
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // 1. Pilih activeFormat terbaik yang mendukung Global Tone Mapping & sRGB,
            //    serta meminimalkan dukungan efek sistem (Portrait/Studio Light/Center Stage)
            if let naturalFormat = selectNaturalUnprocessedFormat(for: device) {
                device.activeFormat = naturalFormat
            }

            // 2. Matikan Auto-HDR & Video HDR agar kontras/kemerahan jerawat tidak diratakan
            device.automaticallyAdjustsVideoHDREnabled = false
            if device.activeFormat.isVideoHDRSupported {
                device.isVideoHDREnabled = false
            }

            // 3. Aktifkan Global Tone Mapping untuk mematikan Local Tone Mapping per-piksel & image fusion
            if device.activeFormat.isGlobalToneMappingSupported {
                device.isGlobalToneMappingEnabled = true
            }

            // 4. Matikan Face-Driven Auto Exposure agar ISP iPhone tidak mencerahkan/meratakan warna kulit wajah
            device.automaticallyAdjustsFaceDrivenAutoExposureEnabled = false
            device.isFaceDrivenAutoExposureEnabled = false
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.minExposureTargetBias <= 0 && device.maxExposureTargetBias >= 0 {
                device.setExposureTargetBias(0.0, completionHandler: nil)
            }

            // 5. Matikan Face-Driven Auto Focus bila didukung agar fokus tetap konsisten di bidang gambar
            device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
            device.isFaceDrivenAutoFocusEnabled = false
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            // 6. Matikan Geometric Distortion Correction agar tidak terjadi upscaling/warping piksel
            if device.isGeometricDistortionCorrectionSupported {
                device.isGeometricDistortionCorrectionEnabled = false
            }

            // 7. Matikan Low-Light Boost & Auto Frame Rate agar tidak terjadi noise smoothing agresif
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = false
            }
            if device.activeFormat.isAutoVideoFrameRateSupported {
                device.isAutoVideoFrameRateEnabled = false
            }

            // 8. Kunci ruang warna ke sRGB standar (tanpa saturasi tambahan P3 Wide Color)
            if device.activeFormat.supportedColorSpaces.contains(.sRGB) {
                device.activeColorSpace = .sRGB
            }

            // 9. Kunci zoom ke 1.0x (tanpa digital crop/upscaling)
            device.videoZoomFactor = 1.0
        } catch {
            print("Gagal mengonfigurasi hardware kamera tanpa pemrosesan: \(error.localizedDescription)")
        }
    }

    /// Memilih format video 30fps beresolusi tinggi (1080p - 4K) yang mendukung `isGlobalToneMappingSupported`
    /// dan meminimalkan efek bawaan iOS.
    nonisolated private func selectNaturalUnprocessedFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let candidateFormats = device.formats.filter { format in
            let mediaType = CMFormatDescriptionGetMediaType(format.formatDescription)
            guard mediaType == kCMMediaType_Video else { return false }

            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            // Gunakan resolusi tajam (minimal 1280px, maksimal 4032px)
            guard dims.width >= 1280 && dims.width <= 4032 && dims.height >= 720 else { return false }

            // Pastikan mendukung 30 fps
            let supports30FPS = format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
            }
            return supports30FPS
        }

        guard !candidateFormats.isEmpty else { return nil }

        // Urutkan kandidat terbaik:
        // 1. Mendukung Global Tone Mapping (mematikan Local Tone Mapping / Smart HDR)
        // 2. Tidak mendukung / tidak memicu efek Portrait / Studio Light / Center Stage bila tersedia
        // 3. Bukan format binned (agar ketajaman pori-pori/jerawat terjaga)
        // 4. Resolusi yang proporsional (~1920x1440 atau 1920x1080 ke atas)
        return candidateFormats.max { lhs, rhs in
            if lhs.isGlobalToneMappingSupported != rhs.isGlobalToneMappingSupported {
                return !lhs.isGlobalToneMappingSupported && rhs.isGlobalToneMappingSupported
            }

            let lhsEffectCount = (lhs.isPortraitEffectSupported ? 1 : 0)
                + (lhs.isStudioLightSupported ? 1 : 0)
                + (lhs.isCenterStageSupported ? 1 : 0)
            let rhsEffectCount = (rhs.isPortraitEffectSupported ? 1 : 0)
                + (rhs.isStudioLightSupported ? 1 : 0)
                + (rhs.isCenterStageSupported ? 1 : 0)
            if lhsEffectCount != rhsEffectCount {
                return lhsEffectCount > rhsEffectCount
            }

            if lhs.isVideoBinned != rhs.isVideoBinned {
                return lhs.isVideoBinned && !rhs.isVideoBinned
            }

            let lhsDims = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rhsDims = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return (lhsDims.width * lhsDims.height) < (rhsDims.width * rhsDims.height)
        }
    }

    /// Mengecek apakah pengguna menyalakan efek video manual di Control Center iOS
    nonisolated private func detectActiveControlCenterEffects(for device: AVCaptureDevice) -> String? {
        var effects: [String] = []
        if device.isPortraitEffectActive {
            effects.append("Potret (Blur)")
        }
        if device.isStudioLightActive {
            effects.append("Lampu Studio")
        }
        if device.isCenterStageActive {
            effects.append("Center Stage")
        }
        if device.isBackgroundReplacementActive {
            effects.append("Pengganti Latar")
        }
        guard !effects.isEmpty else { return nil }
        return effects.joined(separator: ", ")
    }

    /// Membuka menu sistem iOS untuk mematikan Efek Video Control Center jika pengguna menyalakannya secara paksa
    func openSystemVideoEffectsSettings() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    func stopSession() {
        guard isSessionRunning else { return }
        videoQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    /// Dipanggil saat pengguna mulai menekan & menahan (hold) tombol potret ataupun melepasnya
    func setHoldingCaptureButton(_ holding: Bool) {
        if isHoldingCaptureButton == holding { return }
        isHoldingCaptureButton = holding
        isHoldingSnapshot = holding

        if holding {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            // Fallback untuk Simulator apabila sesi kamera tidak berjalan
            if !isSessionRunning {
                let sampleImg = DemoSampleGenerator.renderStylizedFaceImage(for: currentTargetSide)
                saveCapturedImage(sampleImg, for: currentTargetSide)
            }
        } else {
            validHoldFrameCount = 0
            withAnimation(.easeOut(duration: 0.2)) {
                holdProgress = 0.0
            }
        }
    }

    /// Simpan foto untuk satu sisi wajah dan otomatis pindah ke sisi berikutnya
    func saveCapturedImage(_ image: UIImage, for side: FaceSide) {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)

        withAnimation(.easeInOut(duration: 0.2)) {
            showCaptureFlash = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.25)) {
                showCaptureFlash = false
            }
        }

        capturedImages[side] = image.normalizedUpImage()
        holdProgress = 0.0
        validHoldFrameCount = 0
        isCooldownActive = true

        // Cari sisi berikutnya yang belum diambil
        if let nextSide = FaceSide.allCases.first(where: { capturedImages[$0] == nil }) {
            currentTargetSide = nextSide
        }

        // Beri jeda singkat sebelum mengizinkan jepretan sisi berikutnya
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            self.isCooldownActive = false
        }
    }

    /// Reset seluruh hasil jepretan untuk mengulang dari awal
    func resetAllCaptures() {
        capturedImages.removeAll()
        currentTargetSide = .front
        holdProgress = 0.0
        validHoldFrameCount = 0
        isHoldingCaptureButton = false
        isHoldingSnapshot = false
        isCooldownActive = false
    }
}

extension FacePoseCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessingFrame else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        if let cgImage = Self.createCGImage(from: pixelBuffer) {
            latestSampleBufferImage = UIImage(cgImage: cgImage)
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let face = request.results?.first else {
            validHoldFrameCount = 0
            Task { @MainActor in
                self.distanceStatus = .noFace
                self.faceSizeRatio = 0.0
                self.holdProgress = 0.0
            }
            return
        }

        // Hitung ukuran relatif wajah terhadap layar untuk menentukan jarak
        let bbox = face.boundingBox
        let dominantDimension = max(bbox.width, bbox.height)

        let evaluatedStatus: FaceDistanceStatus
        let isOptimalDistance: Bool
        if dominantDimension < minOptimalFaceDimension {
            evaluatedStatus = .tooFar
            isOptimalDistance = false
        } else if dominantDimension > maxOptimalFaceDimension {
            evaluatedStatus = .tooClose
            isOptimalDistance = false
        } else {
            evaluatedStatus = .optimal
            isOptimalDistance = true
        }

        // Hanya hitung progress jepret apabila user sedang HOLD tombol DAN jarak wajah ideal
        if isHoldingSnapshot && isOptimalDistance && !isCooldownActive {
            validHoldFrameCount += 1
        } else if !isHoldingSnapshot {
            validHoldFrameCount = 0
        } else {
            // Jika masih menahan tombol tapi jarak bergeser terlalu dekat/jauh, tahan/kurangi perlahan
            validHoldFrameCount = max(0, validHoldFrameCount - 1)
        }

        let progress = min(1.0, Double(validHoldFrameCount) / Double(requiredHoldFrames))
        let shouldTriggerCapture = validHoldFrameCount >= requiredHoldFrames && !isCooldownActive && isHoldingSnapshot
        let capturedFrame = shouldTriggerCapture ? latestSampleBufferImage : nil

        if shouldTriggerCapture {
            validHoldFrameCount = 0
            isCooldownActive = true
        }

        Task { @MainActor in
            self.distanceStatus = evaluatedStatus
            self.faceSizeRatio = Double(dominantDimension)
            self.holdProgress = progress

            if let capturedFrame, self.capturedImages[self.currentTargetSide] == nil {
                self.saveCapturedImage(capturedFrame, for: self.currentTargetSide)
            }
        }
    }

    nonisolated private static func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return rawCIContext.createCGImage(ciImage, from: ciImage.extent)
    }
}

/// UIViewRepresentable untuk menampilkan preview kamera AVFoundation secara full-screen
struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
