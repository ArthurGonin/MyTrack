//
//  AccountToolbarModifier.swift
//  MyTrack
//
//  Shared top-left account button + settings sheet, applied to every main
//  tab so the entry point to the account is always reachable.
//

import SwiftUI
import SwiftData

private struct AccountToolbarModifier: ViewModifier {
    @Environment(AppServices.self) private var appServices
    @Query private var userProfiles: [UserProfile]
    @State private var isPresentingSettings = false

    private var accountInitial: String {
        let firstName = userProfiles.first?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let first = firstName.first else { return "A" }
        return String(first).uppercased()
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountButton(
                        initial: accountInitial,
                        hasWarning: !appServices.purchaseService.canRecordTrips
                    ) {
                        isPresentingSettings = true
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $isPresentingSettings) {
                AccountSettingsView()
            }
    }
}

extension View {
    func accountToolbar() -> some View {
        modifier(AccountToolbarModifier())
    }
}
