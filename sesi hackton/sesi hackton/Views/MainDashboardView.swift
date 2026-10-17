//
//  MainDashboardView.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import SwiftUI

struct MainDashboardView: View {
    @StateObject private var llmService = FoundationLLMService()
    @StateObject private var speechService = SpeechService()
    @StateObject private var calendarService = CalendarService()

    // Pilihan simulasi hasil deteksi Object Detection teman Anda
    private let presetKeys = Array(AcneDetectionMockData.samplePresets.keys)
        .sorted()
    @State private var selectedPresetKey: String =
        "Kasus 1: Jerawat Meradang (Pustula & Papula)"
    @State private var customAcneInput: String = ""
    @State private var useCustomInput: Bool = false

    // Tanggal target injeksi kalender (Default: Besok)
    @State private var targetCalendarDate: Date =
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 14) {
            // MARK: - 1. Top Bar: Integrasi Object Detection (CV)
            topDetectionControlBar

            // MARK: - 2. Content Area
            if llmService.isGenerating {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(
                        "Apple Foundation Model (M5) sedang menyusun 3 respons sekaligus..."
                    )
                    .font(.headline)
                    Text(
                        "Menghasilkan panduan nutrisi, naskah suara TTS, dan jadwal kalender harian."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
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

                // Split View: Response 1 (Kiri) & Response 3 (Kanan)
                HSplitView {
                    // KIRI: Response 1 (Penjelasan Lengkap Pola Hidup)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Panduan Pola Hidup & Nutrisi Lengkap",
                            systemImage: "leaf.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.green)

                        ScrollView {
                            Text(renderMarkdown(plan.detailedGuideMarkdown))
                                .font(.body)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                    .padding(.trailing, 8)
                    .frame(minWidth: 420, maxWidth: .infinity)

                    // KANAN: Response 3 (Jadwal Harian & Auto-Inject Apple Calendar)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(
                                "Rencana Jadwal Harian",
                                systemImage: "calendar.badge.clock"
                            )
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

                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(plan.dailySchedules) { schedule in
                                    ScheduleCardView(item: schedule)
                                }
                            }
                            .padding(8)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )

                        // Tombol Ekspor ke Apple Calendar
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Button(action: {
                                    Task {
                                        await calendarService
                                            .exportSchedulesToAppleCalendar(
                                                plan.dailySchedules,
                                                targetDate: targetCalendarDate
                                            )
                                    }
                                }) {
                                    Label(
                                        "Masukkan ke Apple Calendar",
                                        systemImage: "calendar.badge.plus"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.large)

                                if calendarService.isExportSuccess {
                                    Button("Buka Kalender") {
                                        calendarService.openAppleCalendarApp()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                }
                            }

                            if !calendarService.exportMessage.isEmpty {
                                Text(calendarService.exportMessage)
                                    .font(.caption)
                                    .foregroundStyle(
                                        calendarService.isExportSuccess
                                            ? .green : .orange
                                    )
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .frame(minWidth: 360, maxWidth: 440)
                }
            } else {
                Spacer()
                ContentUnavailableView(
                    "Siap Menganalisis Deteksi Jerawat",
                    systemImage: "camera.viewfinder",
                    description: Text(
                        "Pilih hasil deteksi Object Detection di atas lalu klik 'Proses dengan Foundation LLM' untuk membuat panduan pola hidup, suara otomatis, dan jadwal kalender."
                    )
                )
                Spacer()
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
        }
        .padding(18)
        .frame(minWidth: 940, minHeight: 640)
    }

    // MARK: - Subview Panel Kontrol Object Detection
    private var topDetectionControlBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AcneCareAI — Holistic Lifestyle & Calendar Assistant")
                        .font(.title3)
                        .bold()
                    Text(
                        "Integrasi Object Detection CV + On-Device LLM + Auto-TTS + EventKit Calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Input Manual dari CV", isOn: $useCustomInput)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 12) {
                if useCustomInput {
                    TextField(
                        "Contoh: 4 Pustula di Pipi, 6 Komedo di Hidung...",
                        text: $customAcneInput
                    )
                    .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Hasil Deteksi CV:", selection: $selectedPresetKey) {
                        ForEach(presetKeys, id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button(action: triggerAnalysis) {
                    Label(
                        "Proses dengan Foundation LLM",
                        systemImage: "sparkles"
                    )
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(llmService.isGenerating)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Actions & Helpers
    private func triggerAnalysis() {
        speechService.stop()

        let itemsToProcess: [DetectedAcneItem]
        if useCustomInput
            && !customAcneInput.trimmingCharacters(in: .whitespaces).isEmpty
        {
            itemsToProcess = [
                DetectedAcneItem(
                    acneType: customAcneInput,
                    facialArea: "Wajah",
                    count: 1,
                    confidence: 0.99
                )
            ]
        } else {
            itemsToProcess =
                AcneDetectionMockData.samplePresets[selectedPresetKey] ?? []
        }

        Task {
            await llmService.generateCompletePlan(from: itemsToProcess)
            // Begitu selesai di-generate, langsung bacakan TTS otomatis!
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
