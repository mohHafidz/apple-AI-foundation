//
//  MainDashboardView.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case guide = "Panduan Nutrisi"
    case schedule = "Jadwal Kalender"

    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .guide: return "leaf.fill"
        case .schedule: return "calendar.badge.clock"
        }
    }
}

struct MainDashboardView: View {
    var initialDetections: [DetectedAcneItem]? = nil

    @StateObject private var llmService = FoundationLLMService()
    @StateObject private var speechService = SpeechService()
    @StateObject private var calendarService = CalendarService()

    // Pilihan simulasi hasil deteksi Object Detection
    private let presetKeys = Array(AcneDetectionMockData.samplePresets.keys).sorted()
    @State private var selectedPresetKey: String = "Kasus 1: Jerawat Meradang (Pustula & Papula)"
    @State private var customAcneInput: String = ""
    @State private var useCustomInput: Bool = false
    @State private var selectedTab: DashboardTab = .guide

    // Tanggal target injeksi kalender (Default: Besok)
    @State private var targetCalendarDate: Date =
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - 1. Top Bar: Integrasi Object Detection (CV)
                topDetectionControlBar

                // MARK: - 2. Content Area
                if llmService.isGenerating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Apple Foundation Model sedang menyusun rencana...")
                            .font(.headline)
                        Text("Menghasilkan panduan nutrisi, naskah suara TTS, dan jadwal kalender harian.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if let plan = llmService.currentPlan {
                    // Komponen Response 2: Banner Suara Otomatis (Gimmick Malas Baca)
                    TTSBannerView(
                        scriptText: plan.ttsSummaryScript,
                        isSpeaking: speechService.isSpeaking,
                        onPlay: {
                            speechService.speakIndonesian(plan.ttsSummaryScript)
                        },
                        onStop: { speechService.stop() }
                    )

                    // Tab Selector: Panduan Lengkap vs Jadwal Kalender
                    Picker("Pilih Tampilan", selection: $selectedTab) {
                        ForEach(DashboardTab.allCases) { tab in
                            Label(tab.rawValue, systemImage: tab.iconName)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)

                    switch selectedTab {
                    case .guide:
                        guideView(markdown: plan.detailedGuideMarkdown)
                    case .schedule:
                        schedulesView(schedules: plan.dailySchedules)
                    }
                } else {
                    ContentUnavailableView(
                        "Siap Menganalisis Deteksi Jerawat",
                        systemImage: "sparkles",
                        description: Text(
                            "Pilih hasil deteksi di atas atau jalankan analisis dari kamera untuk membuat panduan pola hidup, suara otomatis, dan jadwal kalender."
                        )
                    )
                    .padding(.vertical, 30)
                }

                // Footer Status Bar
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(.secondary)
                    Text(llmService.statusLog)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("AcneCare AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let initial = initialDetections, !initial.isEmpty {
                triggerAnalysis(with: initial)
            }
        }
        .onDisappear {
            speechService.stop()
        }
    }

    // MARK: - Subview Panel Kontrol Object Detection
    private var topDetectionControlBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AcneCareAI Lifestyle Plan")
                        .font(.headline)
                        .bold()
                    Text("CV Detection + On-Device AI + Voice + Apple Calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Manual", isOn: $useCustomInput)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if useCustomInput {
                TextField(
                    "Contoh: 4 Pustula di Pipi, 6 Komedo di Hidung...",
                    text: $customAcneInput
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Picker("Deteksi Kasus:", selection: $selectedPresetKey) {
                    ForEach(presetKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: { triggerAnalysis() }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Proses dengan Foundation AI")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(llmService.isGenerating)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Guide View (Response 1)
    private func guideView(markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Panduan Pola Hidup & Nutrisi", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text(renderMarkdown(markdown))
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
        }
    }

    // MARK: - Schedules View (Response 3)
    private func schedulesView(schedules: [LifestyleScheduleItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Rencana Jadwal Harian", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                DatePicker(
                    "Tanggal:",
                    selection: $targetCalendarDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                ForEach(schedules) { schedule in
                    ScheduleCardView(item: schedule)
                }
            }

            // Tombol Ekspor ke Apple Calendar
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: {
                        Task {
                            await calendarService.exportSchedulesToAppleCalendar(
                                schedules,
                                targetDate: targetCalendarDate
                            )
                        }
                    }) {
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
    }

    // MARK: - Actions & Helpers
    private func triggerAnalysis(with customItems: [DetectedAcneItem]? = nil) {
        speechService.stop()

        let itemsToProcess: [DetectedAcneItem]
        if let customItems = customItems {
            itemsToProcess = customItems
        } else if useCustomInput && !customAcneInput.trimmingCharacters(in: .whitespaces).isEmpty {
            itemsToProcess = [
                DetectedAcneItem(
                    acneType: customAcneInput,
                    facialArea: "Wajah",
                    count: 1,
                    confidence: 0.99
                )
            ]
        } else {
            itemsToProcess = AcneDetectionMockData.samplePresets[selectedPresetKey] ?? []
        }

        Task {
            await llmService.generateCompletePlan(from: itemsToProcess)
            // Begitu selesai di-generate, langsung bacakan TTS otomatis
            if let script = llmService.currentPlan?.ttsSummaryScript {
                speechService.speakIndonesian(script)
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
    NavigationStack {
        MainDashboardView()
    }
}
