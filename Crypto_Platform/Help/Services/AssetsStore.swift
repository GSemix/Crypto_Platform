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

    init(symbol: String, name: String, currency: String, price: Double = 0, change: Double = 0, hasPrice: Bool = false) {
        logo = "chart.line.uptrend.xyaxis"
        self.symbol = symbol
        self.name = name
        self.currency = currency
        type = "Популярное"
        self.price = price
        self.change = change
        self.hasPrice = hasPrice
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
    /// Сервер недоступен: показан сохранённый каталог от этого времени
    @Published private(set) var staleSince: Date?

    private let cache = CatalogCache()

    private let baseURL = "https://hse-server.tw1.ru/api"

    func loadAssets(force: Bool = false) async {
        guard assets.isEmpty || force || staleSince != nil else { return }
        // Каталог не старше 5 минут показывается без загрузки
        if !force, assets.isEmpty, let saved = cache.read(), Date().timeIntervalSince(saved.savedAt) < CatalogCache.freshFor {
            assets = saved.assets
            return
        }

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
                let fresh = try JSONDecoder().decode([Asset].self, from: data)
                // Цены, уже известные по прошлой загрузке, сохраняем
                let known = Dictionary((cache.read()?.assets ?? assets).map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
                assets = fresh.map { asset in
                    guard let old = known[asset.symbol], old.hasPrice else { return asset }
                    var merged = asset
                    merged.price = old.price; merged.change = old.change; merged.hasPrice = true
                    return merged
                }
                staleSince = nil
                cache.write(assets)
            } else {
                errorMessage = "Не удалось загрузить активы"
                useCacheIfAvailable()
            }
        } catch {
            errorMessage = error.localizedDescription
            useCacheIfAvailable()
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
        cache.write(assets)
    }

    /// Сервер недоступен: последний сохранённый каталог любой давности с отметкой времени
    private func useCacheIfAvailable() {
        guard let saved = cache.read() else { return }
        if assets.isEmpty { assets = saved.assets }
        staleSince = saved.savedAt
        errorMessage = nil
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


/// Каталог на устройстве (Caches): список активов и последние известные цены
struct CatalogCache {
    static let freshFor: TimeInterval = 5 * 60

    struct Item: Codable {
        let symbol: String, name: String, currency: String
        let price: Double, change: Double, hasPrice: Bool
    }

    struct Saved: Codable {
        let savedAt: Date
        let items: [Item]
        var assets: [Asset] {
            items.map { Asset(symbol: $0.symbol, name: $0.name, currency: $0.currency,
                              price: $0.price, change: $0.change, hasPrice: $0.hasPrice) }
        }
    }

    private let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("catalog.json")

    func read() -> Saved? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }

    func write(_ assets: [Asset]) {
        let saved = Saved(savedAt: Date(), items: assets.map {
            Item(symbol: $0.symbol, name: $0.name, currency: $0.currency, price: $0.price, change: $0.change, hasPrice: $0.hasPrice)
        })
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
    }
}

/// Плашка «показан сохранённый каталог»
struct CatalogOfflineNotice: View {
    @EnvironmentObject var assetsStore: AssetsStore

    var body: some View {
        if let since = assetsStore.staleSince {
            NoticeView(kind: .warning,
                       title: "Нет связи с сервером",
                       message: String(localized: "Показан каталог, сохранённый \(since.formatted(date: .abbreviated, time: .shortened)). Цены могут быть устаревшими."),
                       action: ("Повторить", { Task { await assetsStore.loadAssets(force: true) } }))
        }
    }
}
