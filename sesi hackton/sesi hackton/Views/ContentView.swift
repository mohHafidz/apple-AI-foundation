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

    private enum ResultTab: String, CaseIterable, Identifiable {
        case aiPlan = "Rencana AI"
        case detection = "Hasil Deteksi"

        var id: String { rawValue }
    }

    @State private var stage: AppStage = .scanning
    @State private var cameraManager = FacePoseCameraManager()
    @State private var scanResults: [FaceSideScanResult] = []

    // AI Services
    @StateObject private var llmService = FoundationLLMService()
    @StateObject private var speechService = SpeechService()
    @StateObject private var calendarService = CalendarService()

    // State untuk halaman Hasil
    @State private var selectedResultTab: ResultTab = .aiPlan
    @State private var showAnnotations: Bool = true
    @State private var selectedSideFilter: FaceSide = .front
    @State private var showPhotoPreviewSheet: Bool = false
    @State private var showNoHistoryAlert: Bool = false

    // Tanggal target untuk ekspor jadwal kalender (Default: Besok)
    @State private var targetCalendarDate: Date =
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

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
            .alert("Belum Ada Riwayat Deteksi", isPresented: $showNoHistoryAlert) {
                Button("Jalankan Demo") {
                    runDemoSimulation()
                }
                Button("Batal", role: .cancel) {}
            } message: {
                Text("Lakukan pemindaian wajah 3 sisi terlebih dahulu atau gunakan mode Demo untuk melihat rencana gaya hidup AI.")
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
            return selectedResultTab == .aiPlan ? "Rencana Pemulihan AI" : "Hasil Deteksi Jerawat"
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
                // Tombol Logo AI untuk mengecek riwayat deteksi & rencana gaya hidup
                Button {
                    if !scanResults.isEmpty || llmService.currentPlan != nil {
                        stage = .results
                    } else {
                        showNoHistoryAlert = true
                    }
                } label: {
                    Label("Riwayat AI", systemImage: "sparkles")
                }
                .tint(.purple)
                .accessibilityLabel("Cek Riwayat Deteksi AI")

                Button {
                    runDemoSimulation()
                } label: {
                    Label("Demo", systemImage: "play.circle")
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
                    speechService.stop()
                    cameraManager.resetAllCaptures()
                    stage = .scanning
                    cameraManager.checkPermissionAndStart()
                } label: {
                    Label("Scan Baru", systemImage: "camera.viewfinder")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedResultTab == .detection {
                    Button {
                        showAnnotations.toggle()
                    } label: {
                        Label(
                            showAnnotations ? "Sembunyikan Box" : "Tampilkan Box",
                            systemImage: showAnnotations ? "viewfinder.circle.fill" : "viewfinder.circle"
                        )
                    }
                    .accessibilityLabel("Toggle Bounding Box")
                } else if selectedResultTab == .aiPlan {
                    Button {
                        if speechService.isSpeaking {
                            speechService.stop()
                        } else if let plan = llmService.currentPlan {
                            speechService.speakIndonesian(plan.ttsSummaryScript)
                        }
                    } label: {
                        Image(systemName: speechService.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel("Kontrol Suara AI")
                }
            }
        }
    }

    // MARK: - 1. Layar Scan 3 Sisi Wajah

    private var scannerScreen: some View {
        VStack(spacing: 0) {
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

                faceDistanceOverlay

                if cameraManager.showCaptureFlash {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.85))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)

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
            speechService.stop()
        }
    }

    private var faceDistanceOverlay: some View {
        VStack {
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

    private var holdToCaptureControl: some View {
        let isOptimal = cameraManager.distanceStatus == .optimal
        let isHolding = cameraManager.isHoldingCaptureButton

        return VStack(spacing: 6) {
            ZStack {
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

    // MARK: - 2. Layar Loading Analisis CoreML + Foundation AI

    private var analyzingScreen: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("Menganalisis Wajah & Menyusun Rencana AI...")
                    .font(.headline)
                Text("AcneCareAI sedang berkerja untuk memberikan saran spesial untuk kamu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - 3. Layar Hasil Terpadu (Rencana AI + Hasil Deteksi)

    private var resultsScreen: some View {
        VStack(spacing: 0) {
            // Segmented Picker untuk beralih antara Rencana AI dan Detail Bounding Box Deteksi
            Picker("Mode Tampilan", selection: $selectedResultTab) {
                ForEach(ResultTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemGroupedBackground))

            if selectedResultTab == .aiPlan {
                aiPlanView
            } else {
                detectionResultsView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Tab Konten: Rencana Pemulihan AI
    private var aiPlanView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let plan = llmService.currentPlan {
                    // Response 2: Banner Suara Otomatis (Gimmick Malas Baca)
                    TTSBannerView(
                        scriptText: plan.ttsSummaryScript,
                        isSpeaking: speechService.isSpeaking,
                        onPlay: {
                            speechService.speakIndonesian(plan.ttsSummaryScript)
                        },
                        onStop: { speechService.stop() }
                    )

                    // Response 1: Panduan Nutrisi & Pola Hidup Markdown
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Panduan Pola Hidup & Nutrisi", systemImage: "leaf.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text(renderMarkdown(plan.detailedGuideMarkdown))
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                    }

                    // Response 3: Rencana Jadwal Harian & Apple Calendar
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Jadwal Harian Rekomendasi", systemImage: "calendar.badge.clock")
                                .font(.headline)
                            Spacer()
                            DatePicker(
                                "Target:",
                                selection: $targetCalendarDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .controlSize(.small)
                        }

                        VStack(spacing: 8) {
                            ForEach(plan.dailySchedules) { schedule in
                                ScheduleCardView(item: schedule)
                            }
                        }

                        // Tombol Export EventKit ke Apple Calendar
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Button {
                                    Task {
                                        await calendarService.exportSchedulesToAppleCalendar(
                                            plan.dailySchedules,
                                            targetDate: targetCalendarDate
                                        )
                                    }
                                } label: {
                                    Label("Simpan ke Apple Calendar", systemImage: "calendar.badge.plus")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.regular)

                                if calendarService.isExportSuccess {
                                    Button("Buka Kalender") {
                                        calendarService.openAppleCalendarApp()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }
                            }

                            if !calendarService.exportMessage.isEmpty {
                                Text(calendarService.exportMessage)
                                    .font(.caption)
                                    .foregroundStyle(calendarService.isExportSuccess ? .green : .orange)
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Footer Status Log Foundation Models
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundStyle(.secondary)
                        Text(llmService.statusLog)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 4)

                } else if llmService.isGenerating {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("AI sedang menyusun rencana nutrisi dan jadwal...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                } else {
                    ContentUnavailableView(
                        "Belum Ada Rencana AI",
                        systemImage: "sparkles",
                        description: Text("Lakukan pemindaian wajah atau jalankan demo untuk membuat rencana pola hidup AI.")
                    )
                    .padding(.vertical, 50)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Tab Konten: Hasil Deteksi Wajah CoreML
    private var detectionResultsView: some View {
        List {
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
                    Text("Setiap objek menampilkan daftar kemungkinan dari model CoreML dengan persentase keyakinan tertinggi.")
                }
            }

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

    // MARK: - Konversi Hasil Deteksi YOLO ke AcneDetectionInput (Untuk Foundation AI)
    private var detectedAcneItemsFromScan: [DetectedAcneItem] {
        var items: [DetectedAcneItem] = []
        for result in scanResults {
            var countsByType: [AcneType: (count: Int, totalConfidence: Float)] = [:]
            for detection in result.detections {
                let current = countsByType[detection.topType] ?? (count: 0, totalConfidence: 0)
                countsByType[detection.topType] = (count: current.count + 1, totalConfidence: current.totalConfidence + detection.topConfidence)
            }

            for (type, data) in countsByType {
                let avgConfidence = Double(data.totalConfidence / Float(data.count))
                items.append(
                    DetectedAcneItem(
                        acneType: type.displayName,
                        facialArea: result.side.rawValue,
                        count: data.count,
                        confidence: avgConfidence
                    )
                )
            }
        }

        if items.isEmpty {
            items.append(
                DetectedAcneItem(
                    acneType: "Kondisi Kulit Relatif Bersih",
                    facialArea: "Seluruh Wajah",
                    count: 0,
                    confidence: 0.99
                )
            )
        }
        return items
    }

    // MARK: - Actions

    private func startModelAnalysis() {
        cameraManager.stopSession()
        stage = .analyzing

        let imagesToAnalyze = cameraManager.capturedImages
        Task {
            let results = await AcneAnalyzerService.shared.analyzeAllSides(capturedImages: imagesToAnalyze)
            self.scanResults = results
            self.selectedSideFilter = results.first?.side ?? .front

            let items = self.detectedAcneItemsFromScan
            await llmService.generateCompletePlan(from: items)

            await MainActor.run {
                self.selectedResultTab = .aiPlan
                self.stage = .results
                if let script = llmService.currentPlan?.ttsSummaryScript {
                    speechService.speakIndonesian(script)
                }
            }
        }
    }

    private func runDemoSimulation() {
        cameraManager.stopSession()
        stage = .analyzing

        let demoResults = DemoSampleGenerator.makeDemoScanResults()
        self.scanResults = demoResults
        self.selectedSideFilter = .front

        Task {
            let items = self.detectedAcneItemsFromScan
            await llmService.generateCompletePlan(from: items)

            await MainActor.run {
                self.selectedResultTab = .aiPlan
                self.stage = .results
                if let script = llmService.currentPlan?.ttsSummaryScript {
                    speechService.speakIndonesian(script)
                }
            }
        }
    }

    private func renderMarkdown(_ rawMarkdown: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: rawMarkdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attributed
        }
        return AttributedString(rawMarkdown)
    }
}

#Preview {
    ContentView()
}
