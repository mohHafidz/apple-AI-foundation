//
//  ScheduleCardView.swift
//  sesi hackton
//
//  Created by Training-58 on 17/10/26.
//

import SwiftUI

struct ScheduleCardView: View {
    let item: LifestyleScheduleItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Badge Jam
            VStack(spacing: 2) {
                Text(String(format: "%02d:%02d", item.hour, item.minute))
                    .font(.system(.subheadline, design: .monospaced))
                    .bold()
                Text("\(item.durationMinutes) mnt")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(
                    Color.accentColor.opacity(0.12)
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.category.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                badgeColor(for: item.category).opacity(0.15)
                            )
                        )
                        .foregroundStyle(badgeColor(for: item.category))

                    Spacer()
                }

                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(item.benefitNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
    }

    private func badgeColor(for category: String) -> Color {
        let lower = category.lowercased()
        if lower.contains("nutrisi") { return .green }
        if lower.contains("olahraga") { return .orange }
        if lower.contains("hidrasi") { return .blue }
        return .purple
    }
}
