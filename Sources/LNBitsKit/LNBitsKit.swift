//
//  LNBits.swift
//  Bitcoin Wallet
//
//  Created by Florian Hubl on 07.06.23.
//

import Foundation
import SwiftTor

@available(iOS 13.0, *)
struct ClearnetRequest: RequestType {
    func request(request: URLRequest) async throws -> (Data, URLResponse) {
        return try await URLSession.shared.data(for: request)
    }
}

@available(iOS 13.0, *)
extension SwiftTor: RequestType {
    
}

@available(iOS 13.0, *)
protocol RequestType {
    func request(request: URLRequest) async throws -> (Data, URLResponse)
}

@available(iOS 13.0.0, macOS 12.0.0,  *)
public struct LNBits {
    
    let server: String
    let walletID: String
    let adminKey: String
//    let invoiceKey: String
    
    enum LNBitsRequest: String {
        case balance = "/api/v1/wallet"
        case invoice = "/api/v1/payments"
        case payments = "/api/v1/payments/decode"
        case lnurlp = "/lnurlp/api/v1/links"
        case lnurl = "/lnurlp"
        case lnurlScan = "/api/v1/lnurlscan"
        case paylnurlp = "/api/v1/payments/lnurl"
        case lnurlw = "/withdraw/api/v1/links"
        case boltzsms = "/boltz/api/v1/swap"
        case boltzsmsr = "/boltz/api/v1/swap/refund"
        case boltzrsms = "/boltz/api/v1/swap/reverse"
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }
    
    let requestType: RequestType
    
    public init(server: String, adminKey: String, walletID: String) {
        if server.suffix(6) == ".onion" {
            self.requestType = SwiftTor()
        }else {
            self.requestType = ClearnetRequest()
        }
        self.server = server
        self.walletID = walletID
        self.adminKey = adminKey
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
        let a = try await requestType.request(request: getRequest(for: .balance, method: .get))
        return try JSONDecoder().decode(Balance.self, from: a.0).balance / 1000
    }
    
    public func createInvoice(sats: Int, memo: String? = nil) async throws -> Invoice {
        let a = getRequest(for: .invoice, method: .post, payLoad: "{\"out\": false, \"amount\": \(sats), \"memo\": \"\(memo ?? "")\"}")
        let c = try await requestType.request(request: a)
        return try JSONDecoder().decode(Invoice.self, from: c.0)
    }
    
    public func checkIfPaid(invoice: Invoice) async throws -> Bool {
        let a = getRequest(for: .invoice, method: .get, urlExtention: invoice.paymentHash)
        let b = try await requestType.request(request: a)
        let c = try JSONDecoder().decode(CheckPaid.self, from: b.0)
        return c.paid
    }
    
    public func getName() async throws -> String {
        let a = try await requestType.request(request: getRequest(for: .balance, method: .get))
        return try JSONDecoder().decode(Balance.self, from: a.0).name
    }
    
    public func getBalanceName() async throws -> (Int, String) {
        let a = try await requestType.request(request: getRequest(for: .balance, method: .get))
        let i = try JSONDecoder().decode(Balance.self, from: a.0)
        return (i.balance / 1000, i.name)
    }
    
    public func changeName(newName: String) async throws {
        let request = getRequest(for: .balance, method: .put, urlExtention: newName, admin: true)
        let a = try await requestType.request(request: request)
        print(String(data: a.0, encoding: .utf8)!)
    }
    
    public func decodeInvoice(invoice: String) async throws -> DecodedInvoice {
        let request = getRequest(for: .payments, method: .post, payLoad: "{\"data\": \"\(invoice)\"}")
        let a = try await requestType.request(request: request)
        do {
            let decoded = try JSONDecoder().decode(DecodedInvoice.self, from: a.0)
            return decoded
        }catch {
            try handleError(data: a.0)
            print("LNBitsKit: Fatal Error in decodeInvoice")
            fatalError()
        }
    }
    

    
    public func handleError(data: Data) throws {
        do {
            let decoded = try JSONDecoder().decode(LNBitsError.self, from: data)
            if let error = decoded.detail {
                throw LNBitsErr.error(error)
            }
        }catch LNBitsErr.error(let error){
            throw LNBitsErr.error(error)
        }catch {}
    }
    
    public func payInvoice(invoice: String) async throws {
        let request = getRequest(for: .invoice, method: .post, payLoad: "{\"out\": true, \"bolt11\": \"\(invoice)\"}", admin: true)
        let a = try await requestType.request(request: request)
        do {
            _ = try JSONDecoder().decode(InvoicePaid.self, from: a.0)
        }catch {
            try handleError(data: a.0)
            print("LNBitsKit: Fatal Error in payInvoice")
            fatalError()
        }
    }
    
    // List Transactions
    
    public func getTXs() async throws -> [LNBitsTransaction] {
        let request = getRequest(for: .invoice, method: .get)
        let a = try await requestType.request(request: request)
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
            print("LNBitsKit: Fatal Error in getTXs")
            fatalError()
        }
    }
    
    private func getRequest(for i: LNBitsRequest, method: HTTPMethod, urlExtention: String? = nil, payLoad: String? = nil, admin: Bool = false) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(server)\(i.rawValue)\(urlExtention != nil ? "/" : "")\(urlExtention ?? "")")!)
        print(request.url!.absoluteString)
        request.httpMethod = method.rawValue
        if let payLoad = payLoad {
            request = add(payload: payLoad, request)
        }
        request.addValue(adminKey, forHTTPHeaderField: "X-Api-Key")
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
        let request = getRequest(for: .lnurlp, method: .post, payLoad: "{\"description\": \"\(name ?? "")\", \"amount\": \(standardAmount ?? 1), \"max\": \(max ?? 100000000), \"min\": \(min ?? 1), \"comment_chars\": \(commentChars ?? 100)}")
        let a = try await requestType.request(request: request)
        let lnurl = try JSONDecoder().decode(LNURLPayLink.self, from: a.0)
        return lnurl
    }
    
    public func getPayLinks() async throws -> LNURLPayLinks {
        let request = getRequest(for: .lnurlp, method: .get, urlExtention: "")
        let a = try await requestType.request(request: request)
        let list = try JSONDecoder().decode(LNURLPayLinks.self, from: a.0)
        return list
    }
    
    // Decode LNURL
    
    func decodeLNURL(lnurl: String) async throws -> DecodedLNURL {
        
        let request = getRequest(for: .lnurlScan, method: .get, urlExtention: lnurl)
        
        let a = try await requestType.request(request: request)
        
        a.0.print()
        
        let b = try JSONDecoder().decode(DecodedLNURLType.self, from: a.0)
        
        switch b.kind {
        case .pay:
            let c = try JSONDecoder().decode(DecodedLNURLP.self, from: a.0)
            return DecodedLNURL(lnurl: lnurl, kind: .pay, min: c.minSendable / 1000, max: c.maxSendable / 1000, description: c.description, domain: c.domain, callback: c.callback, descriptionHash: c.descriptionHash)
        case .withdraw:
            let c = try JSONDecoder().decode(DecodedLNURLW.self, from: a.0)
            return DecodedLNURL(lnurl: lnurl, kind: .withdraw, min: c.minWithdrawable / 1000, max: c.maxWithdrawable / 1000, description: c.defaultDescription, domain: c.domain, callback: c.callback, descriptionHash: c.defaultDescription)
        case .auth:
            let c = try JSONDecoder().decode(DecodedLNURLAuth.self, from: a.0)
            return DecodedLNURL(lnurl: lnurl, kind: .auth, domain: c.domain, callback: c.callback)
        }
    }
    
    // Pay LNURL Pay Link
    
    func payLNURL(lnurl: String, amount: Int) async throws {
        let decoded = try await decodeLNURL(lnurl: lnurl)
        print(decoded)
        print(decoded.callback!)
        print(decoded.descriptionHash!)
        guard decoded.kind == .pay else {throw LNBitsErr.error("LNBits Error: LNURL is not a Pay Link")}
        let request = getRequest(for: .paylnurlp, method: .post, payLoad: "{\"description_hash\": \"\(decoded.descriptionHash!)\", \"callback\": \"\(decoded.callback!)\", \"amount\": \(amount * 1000), \"comment\": \"\", \"description\": \"\"}", admin: true)
        _ = try await requestType.request(request: request)
    }
    
    struct DecodedLNURLType: Codable {
        let kind: LNURLType
    }
    
    // Create LNURL
    
    func createLNURLWithdraw(title: String = "Withdraw", min: Int = 1, max: Int = 100000000, uses: Int = 1, waitTime: Int = 1) async throws -> LNURLWithdraw {
        let request = getRequest(for: .lnurlw, method: .post, payLoad: "{\"title\": \"\(title)\", \"min_withdrawable\": \(min), \"max_withdrawable\": \(max), \"uses\": \(uses), \"wait_time\": \(waitTime), \"is_unique\": false, \"webhook_url\": \"\"}", admin: true)
        let lnurl = try await requestType.request(request: request)
        return try JSONDecoder().decode(LNURLWithdraw.self, from: lnurl.0)
    }
    
    // List LNURLW
    
    func getLNURLWithdraws() async throws -> [LNURLWithdraw] {
        let request = getRequest(for: .lnurlw, method: .get, admin: true)
        let lnurl = try await requestType.request(request: request)
        return try JSONDecoder().decode([LNURLWithdraw].self, from: lnurl.0)
    }
    
    // Withdraw LNURL Withdraw Link
    
    func withdrawFromLNURLWithdraw(lnurl: String, amount: Int? = nil, memo: String? = "") async throws {
        let ln = try await decodeLNURL(lnurl: lnurl)
        guard ln.kind == .withdraw else {throw LNBitsErr.error("LNBits Error: LNURL is not a withdraw link")}
        
        let invoice = try await createInvoice(sats: amount ?? ln.max!, memo: memo)
        
        let lnurlBackURL = ln.callback! + "&pr=" + invoice.paymentRequest
        
        var request = URLRequest(url: URL(string: lnurlBackURL)!)
        request.addValue(adminKey, forHTTPHeaderField: "X-Api-Key")
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let result = try await requestType.request(request: request)

        try handleError(data: result.0)
    }
    
    func deleteLNURLPay(id: String) async throws {
        let request = getRequest(for: .lnurlp, method: .delete, urlExtention: id, admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
    }
    
    func deleteLNURLWithdraw(id: String) async throws {
        let request = getRequest(for: .lnurlw, method: .delete, urlExtention: id, admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
    }
    
    func lnurlAuth(lnurl: String) async throws {
        let ln = try await decodeLNURL(lnurl: lnurl)
        
        guard ln.kind == .auth else {throw LNBitsErr.error("LNBits Error: LNURL is not auth")}
        
        var request = URLRequest(url: URL(string: "\(server)/api/v1/lnurlauth")!)
        request.addValue(adminKey, forHTTPHeaderField: "X-Api-Key")
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"callback\": \"\(ln.callback!)\"}".data(using: .utf8)
        
        let result = try await requestType.request(request: request)
        
        try handleError(data: result.0)
    }
    
    // Boltz
    
    // Bitcoin --> Lightning
    
    func createSubMarineSwap(amount: Int, refundAddress: String) async throws -> BoltzSubMarineSwap {
        let request = getRequest(for: .boltzsms, method: .post, payLoad: "{\"wallet\": \"\(walletID)\",\"refund_address\": \"\(refundAddress)\",\"amount\": \"\(amount)\",\"feerate\": false}", admin: true)

        let result = try await requestType.request(request: request)
        result.0.print()
        try handleError(data: result.0)
        let swap = try JSONDecoder().decode(BoltzSubMarineSwap.self, from: result.0)
        return swap
    }

    func getSubMarineSwaps() async throws -> [BoltzSubMarineSwap] {
        let request = getRequest(for: .boltzsms, method: .get)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode([BoltzSubMarineSwap].self, from: result.0)
    }

    // Lightning --> Bitcoin

    func createReversedSubMarineSwap(amount: Int, onChainAddress: String) async throws -> BoltzReversedSubMarineSwap {
        let request = getRequest(for: .boltzrsms, method: .post, payLoad: "{\"wallet\": \"\(walletID)\",\"amount\": \"\(amount)\",\"instant_settlement\": true,\"onchain_address\": \"\(onChainAddress)\"}", admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode(BoltzReversedSubMarineSwap.self, from: result.0)
    }

    func getReversedSubMarineSwaps() async throws -> [BoltzReversedSubMarineSwap] {
        let request = getRequest(for: .boltzrsms, method: .get)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode([BoltzReversedSubMarineSwap].self, from: result.0)
    }

    func refundSubMarineSwap(swapID: String) async throws -> RefundSubMarineSwap {
        let request = getRequest(for: .boltzsmsr, method: .post, payLoad: "{\"swap_id\": \"\(swapID)\"}", admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode(RefundSubMarineSwap.self, from: result.0)
    }
    
}



// --------------------------------- Models ------------------------------------

struct RefundSubMarineSwap: Codable {
    public let id, wallet: String
    public let amount: Int
    public let feerate: Bool
    public let feerateValue: Int
    public let paymentHash: String
    public let time: Int
    public let status, refundPrivkey, refundAddress, boltzID: String
    public let expectedAmount, timeoutBlockHeight: Int
    public let address, bip21, redeemScript: String

    enum CodingKeys: String, CodingKey {
        case id, wallet, amount, feerate
        case feerateValue = "feerate_value"
        case paymentHash = "payment_hash"
        case time, status
        case refundPrivkey = "refund_privkey"
        case refundAddress = "refund_address"
        case boltzID = "boltz_id"
        case expectedAmount = "expected_amount"
        case timeoutBlockHeight = "timeout_block_height"
        case address, bip21
        case redeemScript = "redeem_script"
    }
}


struct BoltzReversedSubMarineSwap: Codable {
    public let id, wallet: String
    public let amount: Int
    public let onchainAddress: String
    public let instantSettlement: Bool
    public let time: Int
    public let status, boltzID, preimage, claimPrivkey: String
    public let lockupAddress, invoice: String
    public let onchainAmount, timeoutBlockHeight: Int
    public let redeemScript: String

    enum CodingKeys: String, CodingKey {
        case id, wallet, amount
        case onchainAddress = "onchain_address"
        case instantSettlement = "instant_settlement"
        case time, status
        case boltzID = "boltz_id"
        case preimage
        case claimPrivkey = "claim_privkey"
        case lockupAddress = "lockup_address"
        case invoice
        case onchainAmount = "onchain_amount"
        case timeoutBlockHeight = "timeout_block_height"
        case redeemScript = "redeem_script"
    }
}

struct BoltzSubMarineSwap: Codable {
    public let id, wallet: String
    public let amount: Int
    public let paymentHash: String
    public let time: Int
    public let status, refundPrivkey, refundAddress, boltzID: String
    public let expectedAmount, timeoutBlockHeight: Int
    public let address, bip21, redeemScript: String

    enum CodingKeys: String, CodingKey {
        case id, wallet, amount
        case paymentHash = "payment_hash"
        case time, status
        case refundPrivkey = "refund_privkey"
        case refundAddress = "refund_address"
        case boltzID = "boltz_id"
        case expectedAmount = "expected_amount"
        case timeoutBlockHeight = "timeout_block_height"
        case address, bip21
        case redeemScript = "redeem_script"
    }
}

struct Status: Codable {
    public let status: String?
    public let detail: String?
    public let success: String?
}

public struct LNURLWithdraw: Codable {
    
    public let id, wallet, title: String
    public let minWithdrawable, maxWithdrawable, uses, waitTime: Int
    public let isUnique: Bool
    public let uniqueHash, k1: String
    public let openTime, used: Int
    public let usescsv: String
    public let number: Int
    public let webhookURL: String
    public let lnurl: String

    enum CodingKeys: String, CodingKey {
        case id, wallet, title
        case minWithdrawable = "min_withdrawable"
        case maxWithdrawable = "max_withdrawable"
        case uses
        case waitTime = "wait_time"
        case isUnique = "is_unique"
        case uniqueHash = "unique_hash"
        case k1
        case openTime = "open_time"
        case used, usescsv, number
        case webhookURL = "webhook_url"
        case lnurl
    }
}

public struct DecodedLNURLP: Codable {
    public let domain, tag: String
    public let callback: String
    public let minSendable, maxSendable: Int
    public let metadata: String
    public let kind: LNURLType
    public let fixed: Bool
    public let descriptionHash, description: String
    public let commentAllowed: Int

    enum CodingKeys: String, CodingKey {
        case domain, tag, callback, minSendable, maxSendable, metadata, kind, fixed
        case descriptionHash = "description_hash"
        case description, commentAllowed
    }
}

public struct DecodedLNURLW: Codable {
    public let domain: String
    public let tag: String
    public let callback: String
    public let k1: String
    public let minWithdrawable, maxWithdrawable: Int
    public let defaultDescription: String
    public let kind: LNURLType
    public let fixed: Bool
}

public struct DecodedLNURLAuth: Codable {
    public let domain: String
    public let kind: LNURLType
    public let callback: String
    public let pubkey: String
}

public struct DecodedLNURL: Codable {
    public let lnurl: String
    public let kind: LNURLType
    public let min, max: Int?
    public let description: String?
    public let domain: String
    public let callback: String?
    public let descriptionHash: String?
    
    init(lnurl: String, kind: LNURLType, min: Int?, max: Int?, description: String?, domain: String, callback: String, descriptionHash: String) {
        self.lnurl = lnurl
        self.kind = kind
        self.min = min
        self.max = max
        self.description = description
        self.domain = domain
        self.callback = callback
        self.descriptionHash = descriptionHash
    }
    
    init(lnurl: String, kind: LNURLType, domain: String, callback: String) {
        self.lnurl = lnurl
        self.kind = kind
        self.callback = callback
        self.min = nil
        self.max = nil
        self.description = nil
        self.descriptionHash = nil
        self.domain = domain
    }
}

public enum LNURLType: String, Codable {
    case pay
    case withdraw
    case auth
}




extension Data {
    func print() {
        Swift.print(String(data: self, encoding: .utf8)!)
    }
    func string() -> String {
        String(data: self, encoding: .utf8)!
    }
}

public typealias LNURLPayLinks = [LNURLPayLink]

public struct LNURLPayLink: Codable {
    public let id: String
    public let wallet: String
    public let min, servedMeta, servedPR: Int
    public let webhookURL, successText, successURL, currency: String?
    public let commentChars, max, fiatBaseMultiplier: Int
    public let lnurl: String
    public let zaps: Bool?
    public let domain: String?

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
    public let name: String
    public let balance: Int
}

public struct Invoice: Codable, Hashable, Equatable {
    public let paymentHash, paymentRequest, checkingID: String

    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case paymentRequest = "payment_request"
        case checkingID = "checking_id"
    }
    
    static let demo = Invoice(paymentHash: "", paymentRequest: "", checkingID: "")
}

public struct LNBitsError: Codable {
    public let detail: String?
}

public struct CheckPaid: Codable {
    public let paid: Bool
    public let preimage: String
}

struct InvoicePaid: Codable {
    public let paymentHash, checkingID: String

    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case checkingID = "checking_id"
    }
}

struct InvoiceUI: Hashable, Equatable {
    public let invoice: Invoice
    public let sats: Int
    
    static let demo = InvoiceUI(invoice: .demo, sats: 11)
}


struct DecodedInvoiceUI: Codable, Hashable {
    public let decoded: DecodedInvoice
    public let bolt11: String
    
    static let demo = DecodedInvoiceUI(decoded: .demo, bolt11: "")
}

public struct DecodedInvoice: Codable, Hashable {
    static public func == (lhs: DecodedInvoice, rhs: DecodedInvoice) -> Bool {
        lhs.paymentHash == rhs.paymentHash
    }
    
    public func hash(into hasher: inout Hasher) {
        
    }
    
        
        static let demo = DecodedInvoice(paymentHash: "", amountMsat: 1, description: "", descriptionHash: nil, payee: "", date: 1, expiry: 1, secret: "", routeHints: [], minFinalCltvExpiry: 1)
        
    public let paymentHash: String
    public let amountMsat: Int
    public let description: String
    public let descriptionHash: JSONNull?
    public let payee: String
    public let date, expiry: Int
    public let secret: String
    public let routeHints: [[RouteHint]]
    public let minFinalCltvExpiry: Int
    
    public var amount: Int {
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

public enum RouteHint: Codable {
        case integer(Int)
        case string(String)

    public init(from decoder: Decoder) throws {
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

public class JSONNull: Codable, Hashable {

        public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
            return true
        }
        
        public func hash(into hasher: inout Hasher) {
        }

        init() {}

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

public enum LNBitsErr: Error {
    case error(String)
}


public typealias LNBitsTransactions = [LNBitsTransaction]
