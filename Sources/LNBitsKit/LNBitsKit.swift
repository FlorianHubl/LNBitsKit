//
//  LNBits.swift
//  Bitcoin Wallet
//
//  Created by Florian Hubl on 07.06.23.
//

import Foundation

@available(iOS 13.0.0, *)
public struct LNBits: Codable {
    
    let server: String
    let adminKey: String
    let invoiceKey: String
    
    enum LNBitsRequest: String {
        case balance = "/api/v1/wallet"
        case invoice = "/api/v1/payments"
        case payments = "/api/v1/payments/decode"
        case lnurlp = "/lnurlp/api/v1/links"
        case lnurl = "/lnurlp"
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }
    
    public init(server: String, adminKey: String, invoiceKey: String) {
        self.server = server
        self.adminKey = adminKey
        self.invoiceKey = invoiceKey
    }
    
    public func testConnection() async -> Bool {
        do {
            _ = try await getBalance()
            return true
        }catch {
            return false
        }
    }
    
    public func getBalance() async throws -> Int {
        let a = try await URLSession.shared.data(for: getRequest(for: .balance, method: .get))
        return try JSONDecoder().decode(Balance.self, from: a.0).balance / 1000
    }
    
    public func createInvoice(sats: Int, memo: String? = nil) async throws -> Invoice {
        let a = getRequest(for: .invoice, method: .post)
        let b = add(payload: "{\"out\": false, \"amount\": \(sats), \"memo\": \"\(memo ?? "")\"}", a)
        let c = try await URLSession.shared.data(for: b)
        return try JSONDecoder().decode(Invoice.self, from: c.0)
    }
    
    public func checkIfPaid(invoice: Invoice) async throws -> Bool {
        let a = getRequest(for: .invoice, method: .get, urlExtention: invoice.paymentHash)
        let b = try await URLSession.shared.data(for: a)
        let c = try JSONDecoder().decode(CheckPaid.self, from: b.0)
        return c.paid
    }
    
    public func getName() async throws -> String {
        let a = try await URLSession.shared.data(for: getRequest(for: .balance, method: .get))
        return try JSONDecoder().decode(Balance.self, from: a.0).name
    }
    
    public func getBalanceName() async throws -> (Int, String) {
        let a = try await URLSession.shared.data(for: getRequest(for: .balance, method: .get))
        let i = try JSONDecoder().decode(Balance.self, from: a.0)
        return (i.balance / 1000, i.name)
    }
    
    public func changeName(newName: String) async throws {
        let request = getRequest(for: .balance, method: .put, urlExtention: newName, admin: true)
        let a = try await URLSession.shared.data(for: request)
        print(String(data: a.0, encoding: .utf8)!)
    }
    
    public func decodeInvoice(invoice: String) async throws -> DecodedInvoice {
        var request = getRequest(for: .payments, method: .post)
        request = add(payload: "{\"data\": \"\(invoice)\"}", request)
        let a = try await URLSession.shared.data(for: request)
        do {
            let decoded = try JSONDecoder().decode(DecodedInvoice.self, from: a.0)
            return decoded
        }catch {
            try handleError(data: a.0)
            fatalError()
        }
    }
    
    public struct LNBitsErr: Error {
        public let errorDescription: String
    }

    
    public func handleError(data: Data) throws {
        let decoded = try? JSONDecoder().decode(LNBitsError.self, from: data)
        if let error = decoded {
            throw LNBitsErr(errorDescription: error.detail)
        }else {
            throw LNBitsErr(errorDescription: "Error in LNBits")
        }
    }
    
    public func payInvoice(invoice: String) async throws {
        var request = getRequest(for: .invoice, method: .post, admin: true)
        request = add(payload: "{\"out\": true, \"bolt11\": \"\(invoice)\"}", request)
        let a = try await URLSession.shared.data(for: request)
        do {
            _ = try JSONDecoder().decode(InvoicePaid.self, from: a.0)
        }catch {
            try handleError(data: a.0)
            fatalError()
        }
    }
    
    public func getTXs() async throws -> [LNBitsTransaction] {
        let request = getRequest(for: .invoice, method: .get)
        let a = try await URLSession.shared.data(for: request)
        do {
            var txs = try JSONDecoder().decode([LNBitsTransaction].self, from: a.0)
            
            for (index, item) in txs.enumerated() {
                txs[index].amount = item.amount / 1000
            }
            
            txs.sort { a, b in
                a.time > b.time
            }
            
            return txs
        }catch {
            print("err")
            try handleError(data: a.0)
            fatalError()
        }
    }
    
    private func getRequest(for i: LNBitsRequest, method: HTTPMethod, urlExtention: String? = nil, admin: Bool = false) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(server)\(i.rawValue)\(urlExtention == nil ? "" : "/\(urlExtention!)")")!)
        print(request.url!.absoluteString)
        request.httpMethod = method.rawValue
        request.addValue(admin ? adminKey : invoiceKey, forHTTPHeaderField: "X-Api-Key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func add(payload: String, _ urlr: URLRequest) -> URLRequest {
        var url = urlr
        print(payload)
        url.httpBody = payload.data(using: .utf8)
        return url
    }
    
    // LNURLPay
    
    public func createLNURLPayLink(name: String? = nil, standardAmount: Int? = nil, min: Int? = nil, max: Int? = nil, commentChars: Int? = nil) async throws -> LNURLPayLink {
        var request = getRequest(for: .lnurlp, method: .post)
        request = add(payload: "{\"description\": \"\(name ?? "")\", \"amount\": \(standardAmount ?? 1), \"max\": \(max ?? 100000000), \"min\": \(min ?? 1), \"comment_chars\": \(commentChars ?? 100)}", request)
        let a = try await URLSession.shared.data(for: request)
        let lnurl = try JSONDecoder().decode(LNURLPayLink.self, from: a.0)
        return lnurl
    }
    
    public func getPayLink() async throws -> LNURLPayLinks {
        let request = getRequest(for: .lnurlp, method: .get, urlExtention: "")
        let a = try await URLSession.shared.data(for: request)
        let list = try JSONDecoder().decode(LNURLPayLinks.self, from: a.0)
        return list
    }
}

extension Data {
    func print() {
        Swift.print(String(data: self, encoding: .utf8)!)
    }
}

public typealias LNURLPayLinks = [LNURLPayLink]

public struct LNURLPayLink: Codable {
    let id: String
    let wallet: String
    let min, servedMeta, servedPR: Int
    let webhookURL, successText, successURL, currency: String?
    let commentChars, max, fiatBaseMultiplier: Int
    let lnurl: String
    let zaps: Bool?
    let domain: String?

    enum CodingKeys: String, CodingKey {
        case id, wallet
        case min
        case servedMeta = "served_meta"
        case servedPR = "served_pr"
        case webhookURL = "webhook_url"
        case successText = "success_text"
        case successURL = "success_url"
        case currency
        case commentChars = "comment_chars"
        case max
        case fiatBaseMultiplier = "fiat_base_multiplier"
        case lnurl
        case zaps
        case domain
    }
}

public struct Balance: Codable {
    let name: String
    let balance: Int
}

public struct Invoice: Codable, Hashable, Equatable {
    let paymentHash, paymentRequest, checkingID: String

    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case paymentRequest = "payment_request"
        case checkingID = "checking_id"
    }
    
    static let demo = Invoice(paymentHash: "", paymentRequest: "", checkingID: "")
}

public struct LNBitsError: Codable {
    let detail: String
}

public struct CheckPaid: Codable {
    let paid: Bool
    let preimage: String
}

struct InvoicePaid: Codable {
    let paymentHash, checkingID: String

    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case checkingID = "checking_id"
    }
}

struct InvoiceUI: Hashable, Equatable {
    let invoice: Invoice
    let sats: Int
    
    static let demo = InvoiceUI(invoice: .demo, sats: 11)
}


struct DecodedInvoiceUI: Codable, Hashable {
    let decoded: DecodedInvoice
    let bolt11: String
    
    static let demo = DecodedInvoiceUI(decoded: .demo, bolt11: "")
}

public struct DecodedInvoice: Codable, Hashable {
    static public func == (lhs: DecodedInvoice, rhs: DecodedInvoice) -> Bool {
        lhs.paymentHash == rhs.paymentHash
    }
    
    public func hash(into hasher: inout Hasher) {
        
    }
    
        
        static let demo = DecodedInvoice(paymentHash: "", amountMsat: 1, description: "", descriptionHash: nil, payee: "", date: 1, expiry: 1, secret: "", routeHints: [], minFinalCltvExpiry: 1)
        
        let paymentHash: String
        let amountMsat: Int
        let description: String
        let descriptionHash: JSONNull?
        let payee: String
        let date, expiry: Int
        let secret: String
        let routeHints: [[RouteHint]]
        let minFinalCltvExpiry: Int
    
    var amount: Int {
        amountMsat * 1000
    }

        enum CodingKeys: String, CodingKey {
            case paymentHash = "payment_hash"
            case amountMsat = "amount_msat"
            case description
            case descriptionHash = "description_hash"
            case payee, date, expiry, secret
            case routeHints = "route_hints"
            case minFinalCltvExpiry = "min_final_cltv_expiry"
        }
    }

    enum RouteHint: Codable {
        case integer(Int)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let x = try? container.decode(Int.self) {
                self = .integer(x)
                return
            }
            if let x = try? container.decode(String.self) {
                self = .string(x)
                return
            }
            throw DecodingError.typeMismatch(RouteHint.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for RouteHint"))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .integer(let x):
                try container.encode(x)
            case .string(let x):
                try container.encode(x)
            }
        }
    }

    // MARK: - Encode/decode helpers

    class JSONNull: Codable, Hashable {

        public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
            return true
        }
        
        public func hash(into hasher: inout Hasher) {
        }

        public init() {}

        public required init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if !container.decodeNil() {
                throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

public struct LNBitsTransaction: Codable {
    let checking_id: String
    let pending: Bool
    var amount: Int
    let fee: Int
    let memo: String
    let time: Int
    let bolt11, preimage, payment_hash: String
    let expiry: Int
    let wallet_id: String
}


typealias LNBitsTransactions = [LNBitsTransaction]
