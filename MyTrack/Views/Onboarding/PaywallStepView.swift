//
//  PaywallStepView.swift
//  MyTrack
//

import SwiftUI

enum PricingPlan: Equatable {
    case annual
    case monthly
}

private enum ComparisonRating {
    case yes
    case no
    case unclear

    var symbolName: String {
        switch self {
        case .yes: "checkmark"
        case .no: "xmark"
        case .unclear: "minus"
        }
    }

    var color: Color {
        switch self {
        case .yes: .green
        case .no: .red
        case .unclear: .orange
        }
    }
}

private struct ComparisonRow: Identifiable {
    let id = UUID()
    let label: String
    let competitorRating: ComparisonRating
}

private let comparisonRows: [ComparisonRow] = [
    ComparisonRow(label: "Sécurité des données", competitorRating: .unclear),
    ComparisonRow(label: "Trajets illimités", competitorRating: .no),
    ComparisonRow(label: "Véhicules illimités", competitorRating: .no),
    ComparisonRow(label: "Rapports PDF inclus", competitorRating: .unclear),
    ComparisonRow(label: "Détection automatique", competitorRating: .unclear),
    ComparisonRow(label: "Prix honnête*", competitorRating: .no),
]

struct PaywallStepView: View {
    @Binding var selectedPlan: PricingPlan
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Pourquoi MyTrack")
                        .font(.largeTitle.bold())

                    comparisonTable

                    Text("* Certaines apps concurrentes facturent en fonction du kilométrage parcouru.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    pricingOptions
                }
            }

            Button("J'y vais") { onContinue() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var comparisonTable: some View {
        Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 16) {
            GridRow {
                Text("")
                Text("MyTrack")
                    .font(.subheadline.bold())
                    .foregroundStyle(.tint)
                Text("Autres apps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(comparisonRows) { row in
                GridRow {
                    Text(row.label)
                        .font(.subheadline)
                        .gridColumnAlignment(.leading)
                    ComparisonBadge(rating: .yes)
                    ComparisonBadge(rating: row.competitorRating)
                }
            }
        }
    }

    private var pricingOptions: some View {
        HStack(spacing: 12) {
            PricingOptionCard(
                isSelected: selectedPlan == .annual,
                title: "7 jours gratuits",
                subtitle: "puis 24,99 $ / an"
            ) {
                selectedPlan = .annual
            }

            PricingOptionCard(
                isSelected: selectedPlan == .monthly,
                title: "2,99 $ / mois",
                subtitle: nil
            ) {
                selectedPlan = .monthly
            }
        }
    }
}

private struct ComparisonBadge: View {
    let rating: ComparisonRating

    var body: some View {
        Image(systemName: rating.symbolName)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(rating.color, in: Circle())
    }
}

private struct PricingOptionCard: View {
    let isSelected: Bool
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                // Reserves the same line height on both cards even when
                // there's no subtitle, so they stay the same size side by side.
                Text(subtitle ?? " ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(subtitle == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallStepView(selectedPlan: .constant(.annual), onContinue: {})
        .appBackground()
}
