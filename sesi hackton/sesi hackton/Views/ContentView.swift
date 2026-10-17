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
    @State private var selectedSideFilter: FaceSide = .leftCheek
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

                                Text("Area \(currentResult.side.rawValue) • \(currentResult.detections.count) objek terdeteksi")
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
            return "Scan 5 Area Wajah"
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

    // MARK: - 1. Layar Scan 5 Area Wajah (Pipi Kiri, Pipi Kanan, Dahi, Hidung, Mulut)

    private var scannerScreen: some View {
        VStack(spacing: 0) {
            // Pilihan 5 Area Wajah (Scrollable Horizontal Pills agar rapi & tidak terpotong)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FaceSide.allCases) { side in
                        let isSelected = cameraManager.currentTargetSide == side
                        let isDone = cameraManager.capturedImages[side] != nil

                        Button {
                            cameraManager.currentTargetSide = side
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isDone ? "checkmark.circle.fill" : side.systemIcon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isDone ? .green : (isSelected ? .white : .secondary))

                                Text(side.shortTabTitle)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

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

                // Panduan Guideline 5 Area Wajah (Pipi Kiri, Pipi Kanan, Dahi, Hidung, Mulut)
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

            // Kontrol Bawah: Status 5 Area + 1 Tombol Hold (Tahan untuk Memotret)
            VStack(spacing: 12) {
                capturedSidesStatusRow

                holdToCaptureControl
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
            // Pill Instruksi Area Fokus Wajah di atas kamera dengan Liquid Glass
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

            // Guideline Visual Khusus untuk 5 Area: Pipi Kiri, Pipi Kanan, Dahi, Hidung, Mulut
            if cameraManager.isCameraAuthorized {
                FacialZoneGuidelineOverlay(
                    targetZone: cameraManager.currentTargetSide,
                    distanceStatus: cameraManager.distanceStatus,
                    holdProgress: cameraManager.holdProgress
                )
            }

            Spacer()

            // Indikator Jarak Wajah Real-time (Terlalu Dekat / Terlalu Jauh / Jarak Ideal)
            if cameraManager.isCameraAuthorized {
                VStack(spacing: 6) {
                    Text(cameraManager.currentTargetSide.guidelineHint)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: .capsule)

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
                }
                .padding(.bottom, 14)
            }
        }
    }

    /// Satu metode tombol: Tahan (Hold) untuk memotret saat jarak wajah tidak terlalu dekat/jauh
    private var holdToCaptureControl: some View {
        let isOptimal = cameraManager.distanceStatus == .optimal
        let isHolding = cameraManager.isHoldingCaptureButton
        let capturedCount = cameraManager.capturedImages.count
        let totalCount = FaceSide.allCases.count

        return VStack(spacing: 6) {
            ZStack {
                // Cincin luar dengan progress melingkar saat ditahan
                Circle()
                    .strokeBorder(
                        isOptimal ? Color.green.opacity(0.45) : Color.primary.opacity(0.25),
                        lineWidth: 4
                    )
                    .frame(width: 76, height: 76)

                if cameraManager.holdProgress > 0 {
                    Circle()
                        .trim(from: 0, to: cameraManager.holdProgress)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(-90))
                }

                // Lingkaran dalam yang mengecil sedikit saat ditekan & ditahan
                Circle()
                    .fill(isOptimal ? Color.green : Color.primary)
                    .frame(width: 60, height: 60)
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
            .accessibilityLabel("Tahan tombol untuk memotret area \(cameraManager.currentTargetSide.rawValue)")
            .accessibilityHint("Pastikan area kulit berada di dalam guideline dan jarak ideal")

            Text(
                isHolding
                ? (isOptimal ? "Tahan sebentar..." : "Sesuaikan jarak area wajah sambil menahan")
                : "Tahan untuk potret \(cameraManager.currentTargetSide.rawValue) (\(capturedCount)/\(totalCount) selesai)"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(isHolding && !isOptimal ? .orange : .secondary)
        }
    }

    private var capturedSidesStatusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FaceSide.allCases) { side in
                    let capturedImg = cameraManager.capturedImages[side]
                    let isSelected = cameraManager.currentTargetSide == side

                    Button {
                        cameraManager.currentTargetSide = side
                    } label: {
                        HStack(spacing: 6) {
                            if let capturedImg {
                                Image(uiImage: capturedImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(.rect(cornerRadius: 6))
                            } else {
                                Image(systemName: side.systemIcon)
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 6))
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(side.shortTabTitle)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(capturedImg != nil ? "Tersimpan" : "Belum")
                                    .font(.system(size: 10))
                                    .foregroundStyle(capturedImg != nil ? .green : .secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
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
    }

    // MARK: - 2. Layar Loading Analisis CoreML

    private var analyzingScreen: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
                .padding(.bottom, 8)
            Text("Menganalisis 5 Area Wajah")
        } description: {
            Text("Model best_yolo_acne sedang mengidentifikasi objek jerawat pada Pipi Kiri, Pipi Kanan, Dahi, Hidung, dan Mulut.")
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - 3. Layar Hasil Deteksi 2D (HIG Inset Grouped List)

    private var resultsScreen: some View {
        List {
            // Section 1: Pilih Area Wajah & Foto Hasil Bounding Box
            if let currentResult = scanResults.first(where: { $0.side == selectedSideFilter }) ?? scanResults.first {
                Section {
                    VStack(spacing: 12) {
                        // Filter 5 Area Wajah
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FaceSide.allCases) { side in
                                    let count = scanResults.first(where: { $0.side == side })?.detections.count ?? 0
                                    let isSelected = selectedSideFilter == side

                                    Button {
                                        selectedSideFilter = side
                                    } label: {
                                        Text("\(side.shortTabTitle) (\(count))")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(
                                                Capsule()
                                                    .fill(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                            )
                                            .foregroundStyle(isSelected ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Image(uiImage: showAnnotations ? currentResult.annotatedImage : currentResult.originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 340)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 14))

                        Button {
                            showPhotoPreviewSheet = true
                        } label: {
                            Label("Perbesar Foto Area \(currentResult.side.rawValue)", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.medium))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Hasil Foto & Bounding Box (5 Area)")
                }

                // Section 2: Daftar Objek & Kemungkinan (Persis seperti Gambar Referensi + HIG Inset Card)
                Section {
                    if currentResult.detections.isEmpty {
                        Label("Tidak ditemukan jerawat pada area \(currentResult.side.rawValue).", systemImage: "checkmark.circle.fill")
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
                self.selectedSideFilter = results.first?.side ?? .leftCheek
                self.stage = .results
            }
        }
    }

    private func runDemoSimulation() {
        cameraManager.stopSession()
        let demoResults = DemoSampleGenerator.makeDemoScanResults()
        self.scanResults = demoResults
        self.selectedSideFilter = .leftCheek
        self.stage = .results
    }
}

// MARK: - Komponen Guideline Visual 5 Area Kulit (Pipi Kiri, Pipi Kanan, Dahi, Hidung, Mulut)

struct FacialZoneGuidelineOverlay: View {
    let targetZone: FaceSide
    let distanceStatus: FaceDistanceStatus
    let holdProgress: Double

    var body: some View {
        ZStack {
            switch targetZone {
            case .leftCheek:
                cheekFocusGuideline(isRightCheek: false)
            case .rightCheek:
                cheekFocusGuideline(isRightCheek: true)
            case .forehead:
                foreheadGuideline
            case .nose:
                noseGuideline
            case .mouth:
                mouthGuideline
            }
        }
        .animation(.easeInOut(duration: 0.25), value: targetZone)
        .animation(.easeInOut(duration: 0.2), value: distanceStatus)
    }

    /// 1 & 2. Guideline untuk Close-Up Pipi Kiri / Pipi Kanan
    private func cheekFocusGuideline(isRightCheek: Bool) -> some View {
        let boxWidth: CGFloat = 236
        let boxHeight: CGFloat = 266

        return ZStack {
            // Patokan anatomi (mata, hidung, rahang)
            VStack(alignment: isRightCheek ? .leading : .trailing, spacing: 18) {
                HStack(spacing: 5) {
                    Image(systemName: "eye")
                        .font(.caption2)
                    Text("Batas Bawah Mata")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.35), in: .capsule)

                Spacer()

                HStack(spacing: 4) {
                    if !isRightCheek {
                        Text("Sisi Hidung")
                            .font(.caption2)
                    }
                    Image(systemName: isRightCheek ? "chevron.compact.left" : "chevron.compact.right")
                        .font(.title3.weight(.bold))
                    if isRightCheek {
                        Text("Sisi Hidung")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: .capsule)

                Spacer()

                Text("Garis Rahang / Pipi Bawah")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.35), in: .capsule)
            }
            .frame(width: boxWidth + 10, height: boxHeight + 10)

            zoneFrameBox(
                title: isRightCheek ? "AREA PIPI KANAN" : "AREA PIPI KIRI",
                width: boxWidth,
                height: boxHeight,
                cornerRadius: 44
            )
        }
    }

    /// 3. Guideline untuk Area Dahi (Forehead)
    private var foreheadGuideline: some View {
        let boxWidth: CGFloat = 272
        let boxHeight: CGFloat = 176

        return ZStack {
            zoneFrameBox(
                title: "AREA DAHI (FOREHEAD)",
                width: boxWidth,
                height: boxHeight,
                cornerRadius: 36
            )

            // Patokan garis alis di bagian bawah bingkai dahi
            VStack {
                Spacer()
                HStack(spacing: 36) {
                    Capsule()
                        .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 76, height: 18)
                        .overlay(
                            Text("Alis Kiri")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        )

                    Capsule()
                        .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 76, height: 18)
                        .overlay(
                            Text("Alis Kanan")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        )
                }
                .offset(y: 28)
            }
            .frame(width: boxWidth, height: boxHeight)
        }
    }

    /// 4. Guideline untuk Area Hidung (Nose & Pori-pori Tengah)
    private var noseGuideline: some View {
        let boxWidth: CGFloat = 190
        let boxHeight: CGFloat = 236

        return ZStack {
            zoneFrameBox(
                title: "AREA HIDUNG",
                width: boxWidth,
                height: boxHeight,
                cornerRadius: 40
            )

            // Siluet garis batang & cuping hidung di tengah
            VStack(spacing: 8) {
                Text("Pangkal Hidung")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 24)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 68, height: 110)

                Text("Cuping Hidung & Pori")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 16)
            }
            .frame(width: boxWidth, height: boxHeight)
        }
    }

    /// 5. Guideline untuk Area Mulut & Dagu (Perioral / Chin)
    private var mouthGuideline: some View {
        let boxWidth: CGFloat = 256
        let boxHeight: CGFloat = 200

        return ZStack {
            zoneFrameBox(
                title: "AREA MULUT & DAGU",
                width: boxWidth,
                height: boxHeight,
                cornerRadius: 38
            )

            // Patokan siluet bibir di tengah agar area kulit sekitar mulut & dagu masuk ke bingkai
            VStack(spacing: 10) {
                Text("Bawah Hidung / Atas Bibir")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 22)

                Capsule()
                    .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 116, height: 38)
                    .overlay(
                        Text("Posisi Bibir")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    )

                Text("Area Dagu & Sudut Mulut")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 14)
            }
            .frame(width: boxWidth, height: boxHeight)
        }
    }

    /// Komponen reusable untuk menggambar kotak fokus, crosshair, badge judul, dan progress tahan tombol
    private func zoneFrameBox(
        title: String,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(distanceStatus.tintColor.opacity(0.06))
                .frame(width: width, height: height)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    distanceStatus.tintColor,
                    style: StrokeStyle(
                        lineWidth: distanceStatus == .optimal ? 4 : 3,
                        dash: distanceStatus == .optimal ? [] : [12, 8]
                    )
                )
                .frame(width: width, height: height)

            // Crosshair grid halus di dalam kotak fokus
            Path { path in
                path.move(to: CGPoint(x: 24, y: height / 2))
                path.addLine(to: CGPoint(x: width - 24, y: height / 2))
                path.move(to: CGPoint(x: width / 2, y: 24))
                path.addLine(to: CGPoint(x: width / 2, y: height - 24))
            }
            .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .frame(width: width, height: height)

            // Badge nama area di bagian atas bingkai
            VStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(distanceStatus.tintColor.opacity(0.88), in: .capsule)
                    .offset(y: -14)
                Spacer()
            }
            .frame(width: width, height: height)

            // Progress ring saat tombol potret sedang ditahan (hold)
            if holdProgress > 0 {
                RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                    .trim(from: 0, to: holdProgress)
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: width + 12, height: height + 12)
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

#Preview {
    ContentView()
}
