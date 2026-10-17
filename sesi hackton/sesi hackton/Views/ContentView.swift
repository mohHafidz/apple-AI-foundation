//
//  ContentView.swift
//  sesi hackton
//
//  Created by Training-57 on 16/10/26.
//

import SwiftUI

struct ContentView: View {
    private enum AppStage {
        case scanning
        case analyzing
        case results
    }

    @State private var stage: AppStage = .scanning
    @State private var cameraManager = FacePoseCameraManager()
    @State private var scanResults: [FaceSideScanResult] = []

    // State untuk halaman Hasil Analisis
    @State private var showAnnotations: Bool = true
    @State private var selectedSideFilter: FaceSide = .front
    @State private var showPhotoPreviewSheet: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .scanning:
                    scannerScreen
                case .analyzing:
                    analyzingScreen
                case .results:
                    resultsScreen
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .onChange(of: cameraManager.isAllCaptured) { _, allDone in
                if allDone && stage == .scanning {
                    cameraManager.setHoldingCaptureButton(false)
                    startModelAnalysis()
                }
            }
            .sheet(isPresented: $showPhotoPreviewSheet) {
                if let currentResult = scanResults.first(where: { $0.side == selectedSideFilter }) ?? scanResults.first {
                    NavigationStack {
                        ScrollView {
                            VStack(spacing: 16) {
                                Image(uiImage: showAnnotations ? currentResult.annotatedImage : currentResult.originalImage)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(.rect(cornerRadius: 16))
                                    .padding(.horizontal)

                                Text("Sisi \(currentResult.side.rawValue) • \(currentResult.detections.count) objek terdeteksi")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical)
                        }
                        .navigationTitle("Foto \(currentResult.side.rawValue)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Selesai") {
                                    showPhotoPreviewSheet = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private var navigationTitleText: String {
        switch stage {
        case .scanning:
            return "Pemindaian Wajah"
        case .analyzing:
            return "Menganalisis..."
        case .results:
            return "Hasil Analisis Jerawat"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch stage {
        case .scanning:
            ToolbarItem(placement: .topBarLeading) {
                if !cameraManager.capturedImages.isEmpty {
                    Button("Ulangi", role: .destructive) {
                        cameraManager.resetAllCaptures()
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    runDemoSimulation()
                } label: {
                    Label("Demo", systemImage: "sparkles")
                }

                if !cameraManager.capturedImages.isEmpty {
                    Button("Analisis") {
                        startModelAnalysis()
                    }
                    .fontWeight(.semibold)
                }
            }

        case .analyzing:
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView()
            }

        case .results:
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    cameraManager.resetAllCaptures()
                    scanResults.removeAll()
                    stage = .scanning
                    cameraManager.checkPermissionAndStart()
                } label: {
                    Label("Scan Baru", systemImage: "camera.viewfinder")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showAnnotations.toggle()
                } label: {
                    Label(
                        showAnnotations ? "Sembunyikan Box" : "Tampilkan Box",
                        systemImage: showAnnotations ? "viewfinder.circle.fill" : "viewfinder.circle"
                    )
                }
                .accessibilityLabel("Toggle Bounding Box")
            }
        }
    }

    // MARK: - 1. Layar Scan 3 Sisi Wajah (1 Metode: Hold Button + Cek Jarak Ideal)

    private var scannerScreen: some View {
        VStack(spacing: 0) {
            // Segmented Picker standar HIG untuk berpindah/melihat sisi wajah
            Picker("Sisi Wajah", selection: $cameraManager.currentTargetSide) {
                ForEach(FaceSide.allCases) { side in
                    let done = cameraManager.capturedImages[side] != nil
                    Text(done ? "✓ \(side.rawValue)" : side.rawValue)
                        .tag(side)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Viewfinder Kamera
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                if cameraManager.isCameraAuthorized {
                    CameraPreviewLayerView(session: cameraManager.session)
                        .clipShape(.rect(cornerRadius: 24))
                } else {
                    ContentUnavailableView {
                        Label("Kamera Tidak Tersedia", systemImage: "camera.fill")
                    } description: {
                        Text(cameraManager.cameraErrorMessage ?? "Berikan izin kamera di Pengaturan atau gunakan mode simulasi.")
                    } actions: {
                        Button("Coba Simulasi") {
                            runDemoSimulation()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }

                // Panduan Jarak Wajah & Banner Instruksi dengan Liquid Glass
                faceDistanceOverlay

                // Efek Flash saat memotret
                if cameraManager.showCaptureFlash {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.85))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)

            // Kontrol Bawah: Status 3 Sisi + 1 Tombol Hold (Tahan untuk Memotret)
            VStack(spacing: 14) {
                capturedSidesStatusRow

                holdToCaptureControl
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            cameraManager.checkPermissionAndStart()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    private var faceDistanceOverlay: some View {
        VStack {
            // Pill Instruksi Sisi Wajah di atas kamera dengan Liquid Glass
            HStack(spacing: 10) {
                Image(systemName: cameraManager.currentTargetSide.systemIcon)
                    .font(.headline)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cameraManager.currentTargetSide.instructionTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(cameraManager.currentTargetSide.instructionSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 14)
            .padding(.horizontal, 16)

            Spacer()

            // Bingkai Elips Panduan Jarak Wajah + Ring Progress saat Tombol Ditahan
            if cameraManager.isCameraAuthorized {
                ZStack {
                    Ellipse()
                        .stroke(
                            cameraManager.distanceStatus.tintColor,
                            style: StrokeStyle(
                                lineWidth: cameraManager.distanceStatus == .optimal ? 4 : 3,
                                dash: cameraManager.distanceStatus == .optimal ? [] : [10, 8]
                            )
                        )
                        .frame(width: 220, height: 286)
                        .animation(.easeInOut(duration: 0.2), value: cameraManager.distanceStatus)

                    if cameraManager.holdProgress > 0 {
                        Ellipse()
                            .trim(from: 0, to: cameraManager.holdProgress)
                            .stroke(
                                Color.green,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 230, height: 296)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: cameraManager.holdProgress)
                    }
                }
            }

            Spacer()

            // Indikator Jarak Wajah Real-time (Terlalu Dekat / Terlalu Jauh / Jarak Ideal)
            if cameraManager.isCameraAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: cameraManager.distanceStatus.systemIcon)
                        .foregroundStyle(cameraManager.distanceStatus.tintColor)
                        .font(.subheadline.weight(.semibold))

                    if cameraManager.isHoldingCaptureButton {
                        if cameraManager.distanceStatus == .optimal {
                            Text("Menahan... \(Int(cameraManager.holdProgress * 100))% (Jarak Ideal)")
                                .font(.caption.weight(.semibold))
                        } else {
                            Text(cameraManager.distanceStatus.title)
                                .font(.caption.weight(.semibold))
                        }
                    } else {
                        Text(cameraManager.distanceStatus.title)
                            .font(.caption.weight(.medium))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 14)
            }
        }
    }

    /// Satu metode tombol: Tahan (Hold) untuk memotret saat jarak wajah tidak terlalu dekat/jauh
    private var holdToCaptureControl: some View {
        let isOptimal = cameraManager.distanceStatus == .optimal
        let isHolding = cameraManager.isHoldingCaptureButton

        return VStack(spacing: 6) {
            ZStack {
                // Cincin luar dengan progress melingkar saat ditahan
                Circle()
                    .strokeBorder(
                        isOptimal ? Color.green.opacity(0.45) : Color.primary.opacity(0.25),
                        lineWidth: 4
                    )
                    .frame(width: 78, height: 78)

                if cameraManager.holdProgress > 0 {
                    Circle()
                        .trim(from: 0, to: cameraManager.holdProgress)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 78, height: 78)
                        .rotationEffect(.degrees(-90))
                }

                // Lingkaran dalam yang mengecil sedikit saat ditekan & ditahan
                Circle()
                    .fill(isOptimal ? Color.green : Color.primary)
                    .frame(width: 62, height: 62)
                    .scaleEffect(isHolding ? 0.86 : 1.0)
                    .animation(.spring(duration: 0.2), value: isHolding)

                Image(systemName: isHolding ? "hand.tap.fill" : "camera.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isOptimal ? .white : Color(uiColor: .systemBackground))
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        cameraManager.setHoldingCaptureButton(true)
                    }
                    .onEnded { _ in
                        cameraManager.setHoldingCaptureButton(false)
                    }
            )
            .accessibilityLabel("Tahan tombol untuk memotret sisi \(cameraManager.currentTargetSide.rawValue)")
            .accessibilityHint("Pastikan jarak wajah ideal, tidak terlalu dekat dan tidak terlalu jauh")

            Text(
                isHolding
                ? (isOptimal ? "Tahan sebentar..." : "Sesuaikan jarak wajah sambil menahan")
                : "Tahan tombol untuk memotret \(cameraManager.currentTargetSide.rawValue)"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(isHolding && !isOptimal ? .orange : .secondary)
        }
    }

    private var capturedSidesStatusRow: some View {
        HStack(spacing: 10) {
            ForEach(FaceSide.allCases) { side in
                let capturedImg = cameraManager.capturedImages[side]
                let isSelected = cameraManager.currentTargetSide == side

                Button {
                    cameraManager.currentTargetSide = side
                } label: {
                    HStack(spacing: 8) {
                        if let capturedImg {
                            Image(uiImage: capturedImg)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(.rect(cornerRadius: 6))
                        } else {
                            Image(systemName: side.systemIcon)
                                .font(.caption)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 6))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(side.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(capturedImg != nil ? "Tersimpan" : "Belum")
                                .font(.caption2)
                                .foregroundStyle(capturedImg != nil ? .green : .secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 2. Layar Loading Analisis CoreML

    private var analyzingScreen: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
                .padding(.bottom, 8)
            Text("Menganalisis 3 Sisi Wajah")
        } description: {
            Text("Model best_yolo_acne sedang mengidentifikasi objek jerawat dan memilih persentase keyakinan tertinggi.")
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - 3. Layar Hasil Deteksi 2D (HIG Inset Grouped List)

    private var resultsScreen: some View {
        List {
            // Section 1: Pilih Sisi Wajah & Foto Hasil Bounding Box
            if let currentResult = scanResults.first(where: { $0.side == selectedSideFilter }) ?? scanResults.first {
                Section {
                    VStack(spacing: 12) {
                        Picker("Pilih Sisi Wajah", selection: $selectedSideFilter) {
                            ForEach(FaceSide.allCases) { side in
                                let count = scanResults.first(where: { $0.side == side })?.detections.count ?? 0
                                Text("\(side.rawValue) (\(count))")
                                    .tag(side)
                            }
                        }
                        .pickerStyle(.segmented)

                        Image(uiImage: showAnnotations ? currentResult.annotatedImage : currentResult.originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 340)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 14))

                        Button {
                            showPhotoPreviewSheet = true
                        } label: {
                            Label("Perbesar Foto Sisi \(currentResult.side.rawValue)", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.medium))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Hasil Foto & Bounding Box")
                }

                // Section 2: Daftar Objek & Kemungkinan (Persis seperti Gambar Referensi + HIG Inset Card)
                Section {
                    if currentResult.detections.isEmpty {
                        Label("Tidak ditemukan jerawat pada sisi \(currentResult.side.rawValue).", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(Array(currentResult.detections.enumerated()), id: \.element.id) { index, detection in
                            detectionHIGRow(index: index + 1, detection: detection)
                        }
                    }
                } header: {
                    Text("Hasil Identifikasi Objek (\(currentResult.side.rawValue))")
                } footer: {
                    Text("Setiap objek menampilkan daftar kemungkinan dari model dan secara otomatis mengambil persentase keyakinan (confidence) tertinggi.")
                }
            }

            // Section 3: Legenda Warna Bounding Box & Ringkasan Jumlah
            Section("Kategori & Warna Bounding Box") {
                let allDetections = scanResults.flatMap(\.detections)
                ForEach([AcneType.whitehead, .pustule, .papule, .nodule, .blackhead]) { type in
                    let count = allDetections.filter { $0.topType == type }.count
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(type.color)
                            .frame(width: 18, height: 18)

                        Text(type.displayName)
                            .font(.body)

                        Spacer()

                        Text("\(count) objek")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func detectionHIGRow(index: Int, detection: AcneDetection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(detection.topType.color)
                        .frame(width: 10, height: 10)
                    Text("Objek #\(index)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Dipilih: \(detection.topType.shortName) (\(detection.topPercentageInt)%)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(detection.topType.color.opacity(0.16), in: .capsule)
                    .foregroundStyle(detection.topType.color)
            }

            VStack(alignment: .leading, spacing: 0) {
                let candidates = Array(detection.allCandidates.prefix(3))
                ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, candidate in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(candidate.label)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if idx == 0 {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(detection.topType.color)
                            }
                        }

                        Text("\(candidate.percentageInt)% confidence")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)

                    if idx < candidates.count - 1 {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(detection.topType.color.opacity(0.65), lineWidth: 1.5)
                    )
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func startModelAnalysis() {
        cameraManager.stopSession()
        stage = .analyzing

        let imagesToAnalyze = cameraManager.capturedImages
        Task {
            let results = await AcneAnalyzerService.shared.analyzeAllSides(capturedImages: imagesToAnalyze)
            await MainActor.run {
                self.scanResults = results
                self.selectedSideFilter = results.first?.side ?? .front
                self.stage = .results
            }
        }
    }

    private func runDemoSimulation() {
        cameraManager.stopSession()
        let demoResults = DemoSampleGenerator.makeDemoScanResults()
        self.scanResults = demoResults
        self.selectedSideFilter = .front
        self.stage = .results
    }
}

#Preview {
    ContentView()
}
