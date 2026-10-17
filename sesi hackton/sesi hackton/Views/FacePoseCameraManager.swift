//
//  FacePoseCameraManager.swift
//  sesi hackton
//
//  Created by Antigravity on 16/10/26.
//

import AVFoundation
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

    // State internal yang diakses di videoQueue (nonisolated)
    nonisolated(unsafe) private var latestSampleBufferImage: UIImage?
    nonisolated(unsafe) private var isProcessingFrame: Bool = false
    nonisolated(unsafe) private var isHoldingSnapshot: Bool = false
    nonisolated(unsafe) private var isCooldownActive: Bool = false
    nonisolated(unsafe) private var validHoldFrameCount: Int = 0
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
                Task { @MainActor in
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
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

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

            self.session.addInput(input)

            // Nonaktifkan efek Cinematic Video (blur/depth sintetis) bila didukung
            if input.isCinematicVideoCaptureSupported {
                input.isCinematicVideoCaptureEnabled = false
            }

            // Matikan Auto-HDR & pemrosesan tambahan pada perangkat kamera
            // (dilakukan setelah addInput & sessionPreset agar tidak ter-reset)
            self.configureUnprocessedCameraHardware(for: cameraDevice)

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
                if cameraDevice.position == .front, connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
                // Matikan stabilisasi video agar frame tidak mengalami resampling/penghalusan piksel
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .off
                }
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            Task { @MainActor in
                self.isSessionRunning = true
            }
        }
    }

    /// Matikan Auto-HDR, Local Tone Mapping, Low-Light Boost, dan Center Stage
    /// agar tekstur dan warna kulit terekam apa adanya tanpa penghalusan tambahan.
    nonisolated private func configureUnprocessedCameraHardware(for device: AVCaptureDevice) {
        // Nonaktifkan Center Stage agar kamera tidak melakukan digital zoom/upscaling otomatis
        if AVCaptureDevice.centerStageControlMode == .cooperative || AVCaptureDevice.centerStageControlMode == .app {
            AVCaptureDevice.isCenterStageEnabled = false
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // 1. Matikan Auto-HDR & Video HDR agar kontras/kemerahan jerawat tidak diratakan
            device.automaticallyAdjustsVideoHDREnabled = false
            if device.activeFormat.isVideoHDRSupported {
                device.isVideoHDREnabled = false
            }

            // 2. Gunakan Global Tone Mapping untuk mematikan local tone mapping per-piksel & image fusion
            if device.activeFormat.isGlobalToneMappingSupported {
                device.isGlobalToneMappingEnabled = true
            }

            // 3. Matikan Low-Light Boost otomatis agar tidak terjadi noise smoothing agresif
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = false
            }
        } catch {
            print("Gagal mengonfigurasi hardware kamera tanpa pemrosesan: \(error.localizedDescription)")
        }
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
        if dominantDimension < minOptimalFaceDimension {
            evaluatedStatus = .tooFar
        } else if dominantDimension > maxOptimalFaceDimension {
            evaluatedStatus = .tooClose
        } else {
            evaluatedStatus = .optimal
        }

        // Hanya hitung progress jepret apabila user sedang HOLD tombol DAN jarak wajah ideal
        if isHoldingSnapshot && evaluatedStatus == .optimal && !isCooldownActive {
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
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
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
