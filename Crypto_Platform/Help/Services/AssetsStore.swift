//
//  AssetStore.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 06.01.2026.
//

import SwiftUI
import Combine

/*struct StockCollection: Identifiable {
    let id = UUID()
    let logo: String        // имя картинки (SF Symbol или asset)
    let title: String       // название (“Apple”)
    let short: String       // сокращённое (“AAPL”)
    let price: Double
    let change: Double      // в процентах
    let category: String
}

let allCollections: [StockCollection] = [
    StockCollection(logo: "apple.logo", title: "Apple", short: "AAPL", price: 182.4, change: +1.24, category: "Технологии"),
    StockCollection(logo: "windows", title: "Microsoft", short: "MSFT", price: 412.3, change: +0.53, category: "Технологии")
]*/

struct Asset: Identifiable, Decodable {
    let id = UUID()
    let logo: String        // имя картинки (SF Symbol или asset)
    let symbol: String      // сокращённое ("AAPL")
    let name: String        // название ("Apple")
    let currency: String
    let type: String

    // Цены API в /assets не отдаёт — подтягиваются из /assets/{symbol}/history
    var price: Double = 0
    var change: Double = 0  // в процентах за окно истории
    var hasPrice: Bool = false

    enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case currency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        logo = "chart.line.uptrend.xyaxis"
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        currency = try c.decode(String.self, forKey: .currency)
        type = "Популярное"
    }
}

// MARK: - /api/assets/{symbol}/history

struct AssetHistoryPoint: Decodable {
    let timestamp: String
    let price: Double
    let low: Double
    let high: Double
    let samples: Double

    var date: Date? {
        AssetHistoryResponse.parseDate(timestamp)
    }
}

struct AssetHistoryResponse: Decodable {
    let symbol: String
    let from: String
    let to: String
    let interval: String
    let count: Int
    let points: [AssetHistoryPoint]

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ value: String) -> Date? {
        plain.date(from: value) ?? fractional.date(from: value)
    }
}

@MainActor
final class AssetsStore: ObservableObject {
    @Published private(set) var assets: [Asset] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let baseURL = "https://hse-server.tw1.ru/api"

    func loadAssets() async {
        guard assets.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/assets") else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                assets = try JSONDecoder().decode([Asset].self, from: data)
            } else {
                errorMessage = "Не удалось загрузить активы"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Цена одного актива — по запросу, когда пользователь открыл его карточку.
    /// Массово на старте не грузим: /assets цен не отдаёт, а history — тяжёлая
    /// агрегация на стороне сервера, десять параллельных запросов его роняют.
    func loadPrice(for symbol: String) async {
        guard
            let index = assets.firstIndex(where: { $0.symbol == symbol }),
            !assets[index].hasPrice,
            let history = await fetchHistory(symbol: symbol, hoursBack: 6),
            let last = history.points.last,
            let first = history.points.first
        else { return }

        assets[index].price = last.price
        assets[index].change = first.price == 0
            ? 0
            : (last.price - first.price) / first.price * 100
        assets[index].hasPrice = true
    }

    /// GET /api/assets/{symbol}/history — параметры называются from/to (не date_from/date_to)
    func fetchHistory(
        symbol: String,
        hoursBack: Int
    ) async -> AssetHistoryResponse? {
        let to = Date()
        let from = to.addingTimeInterval(-Double(hoursBack) * 3600)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var components = URLComponents(
            string: "\(baseURL)/assets/\(symbol)/history"
        )
        components?.queryItems = [
            URLQueryItem(name: "from", value: iso.string(from: from)),
            URLQueryItem(name: "to", value: iso.string(from: to))
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(AssetHistoryResponse.self, from: data)
        } catch {
            return nil
        }
    }
}

