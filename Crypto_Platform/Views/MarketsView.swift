//
//  MarketsView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 18.11.2025.
//

import SwiftUI

struct MarketsView: View {
    @State private var searchText = ""
    @EnvironmentObject var assetsStore: AssetsStore

    var filtered: [Asset] {
        guard !searchText.isEmpty else { return assetsStore.assets }
        let query = searchText.lowercased()
        return assetsStore.assets.filter {
            $0.name.lowercased().contains(query)
                || $0.symbol.lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if assetsStore.assets.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                EmptyStateView(
                    title: "Ничего не найдено",
                    message: String(localized: "Попробуйте другой тикер или название")
                )
            } else {
                ScrollView {
                    VStack(spacing: Spacing.m) {
                    CatalogOfflineNotice()
                    DataGroup {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, stock in
                            if index > 0 { HairlineDivider() }

                            NavigationLink {
                                AssetDetailScreen(stock: stock)
                            } label: {
                                MarketRow(
                                    ticker: stock.symbol,
                                    name: stock.name,
                                    price: stock.price,
                                    change: stock.change,
                                    hasPrice: stock.hasPrice
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    }
                    .padding(Spacing.m)
                }
            }
        }
        .navigationTitle("Рынки")
        .searchable(text: $searchText, prompt: "Тикер или название")
    }
}
