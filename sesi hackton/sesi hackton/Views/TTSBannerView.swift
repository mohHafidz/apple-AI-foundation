//
//  TTSBannerView.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import SwiftUI

struct TTSBannerView: View {
    let scriptText: String
    let isSpeaking: Bool
    let onPlay: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        isSpeaking
                            ? Color.orange.opacity(0.2)
                            : Color.accentColor.opacity(0.15)
                    )
                    .frame(width: 44, height: 44)

                Image(
                    systemName: isSpeaking
                        ? "waveform.circle.fill"
                        : "speaker.wave.2.bubble.left.fill"
                )
                .font(.system(size: 22))
                .foregroundStyle(isSpeaking ? .orange : .accentColor)
                .symbolEffect(.pulse, isActive: isSpeaking)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Mode Malas Baca (Ringkasan Suara AI)")
                        .font(.headline)

                    if isSpeaking {
                        Text("• Sedang Dibacakan...")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Button(action: isSpeaking ? onStop : onPlay) {
                        Label(
                            isSpeaking ? "Hentikan Suara" : "Putar Ulang Suara",
                            systemImage: isSpeaking ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSpeaking ? .orange : .accentColor)
                    .controlSize(.small)
                }

                Text("\"\(scriptText)\"")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSpeaking
                                ? Color.orange.opacity(0.6)
                                : Color.secondary.opacity(0.2),
                            lineWidth: 1.5
                        )
                )
        )
    }
}
