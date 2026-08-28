//
//  AssetChartView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//
//  График цены — GET /api/assets/{symbol}/history

import SwiftUI
import Charts

struct PricePoint: Identifiable {
    let id = UUID()
    let time: Date
    let price: Double
}

enum ChartRange: String, CaseIterable, Identifiable {
    case hour6 = "6ч"
    case day = "24ч"
    case week = "7д"
    case month = "30д"

    var id: String { rawValue }

    var hoursBack: Int {
        switch self {
        case .hour6: return 6
        case .day:   return 24
        case .week:  return 24 * 7
        case .month: return 24 * 30
        }
    }
}

struct PriceChart: View {
    let points: [PricePoint]

    private var priceRange: ClosedRange<Double> {
        let prices = points.map(\.price)
        guard let min = prices.min(), let max = prices.max() else {
            return 0...1
        }
        // небольшой отступ, чтобы линия не липла к краям
        let padding = Swift.max((max - min) * 0.1, 0.01)
        return (min - padding)...(max + padding)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Время", point.time),
                    y: .value("Цена", point.price)
                )
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Время", point.time),
                    yStart: .value("Мин", priceRange.lowerBound),
                    yEnd: .value("Цена", point.price)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    .linearGradient(
                        colors: [.accentColor.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartYScale(domain: priceRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.day().month().hour())
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 250)
    }
}

struct AssetChartView: View {
    let name: String
    /// Тикер для API (без валюты)
    let symbol: String
    /// Что показать в заголовке, например "NVR/USD"
    let displayTitle: String

    @EnvironmentObject var assetsStore: AssetsStore

    @State private var range: ChartRange = .day
    @State private var points: [PricePoint] = []
    @State private var currentPrice: Double?
    @State private var changePercent: Double = 0
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 16) {

            Text(displayTitle)
                .font(.title)
                .fontWeight(.bold)

            if let currentPrice {
                Text(formatPrice(currentPrice) + " $")
                    .font(.title2)
                    .foregroundStyle(changePercent >= 0 ? .green : .red)

                Text("\(changePercent >= 0 ? "+" : "")\(String(format: "%.2f%%", changePercent)) за \(range.rawValue)")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            } else if isLoading {
                Text("—")
                    .font(.title2)
                    .foregroundStyle(Palette.secondaryText)
            }

            Picker("Период", selection: $range) {
                ForEach(ChartRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)

            if isLoading {
                ProgressView()
                    .frame(height: 250)
            } else if loadFailed || points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundStyle(Palette.secondaryText)
                    Text("Нет данных за период")
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(height: 250)
            } else {
                PriceChart(points: points)
            }

            Spacer()
        }
        .padding()
        .task(id: range) {
            await load()
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        guard let history = await assetsStore.fetchHistory(
            symbol: symbol,
            hoursBack: range.hoursBack
        ) else {
            loadFailed = true
            return
        }

        points = history.points.compactMap { point in
            guard let date = point.date else { return nil }
            return PricePoint(time: date, price: point.price)
        }

        currentPrice = points.last?.price

        if let first = points.first?.price,
           let last = points.last?.price,
           first != 0 {
            changePercent = (last - first) / first * 100
        } else {
            changePercent = 0
        }

        // заодно проставляем цену в списке активов
        await assetsStore.loadPrice(for: symbol)
    }
}
