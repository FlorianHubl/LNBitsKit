//
//  LNBits.swift
//  Bitcoin Wallet
//
//  Created by Florian Hubl on 07.06.23.
//

import Foundation
import SwiftTor

public enum DebugLevel {
    case zero
    case urls
    case all
}

class TrustSession: NSObject, URLSessionDelegate {
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
           let urlCredential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
           completionHandler(.useCredential, urlCredential)
        }
}

@available(iOS 13.0.0, macOS 12.0.0, *)
struct ClearnetTrustRequest: RequestType {
    func request(request: URLRequest) async throws -> (Data, URLResponse) {
        return try await URLSession(configuration: URLSessionConfiguration.default, delegate: TrustSession(), delegateQueue: nil).data(for: request)
    }
}

@available(iOS 13.0.0, macOS 12.0.0, *)
struct ClearnetRequest: RequestType {
    func request(request: URLRequest) async throws -> (Data, URLResponse) {
            return try await URLSession.shared.data(for: request)
    }
}

@available(iOS 13.0, macOS 13.0, *)
extension SwiftTor: RequestType {
    
}

@available(iOS 13.0, macOS 13.0, *)
protocol RequestType {
    func request(request: URLRequest) async throws -> (Data, URLResponse)
}

@available(iOS 13.0.0, macOS 13.0.0,  *)
public struct LNBits {
    
    public let server: String
    public let walletID: String?
    public let adminKey: String
    public let user: String?

//    let invoiceKey: String
    
    enum LNBitsRequest: String {
        case wallet = "/usermanager/api/v1/wallets"
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
        case login = "/api/v1/auth"
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }
    
    let requestType: RequestType
    
    public var connection = false
    
    let debug: DebugLevel
    
    public let tor: Bool
    
    public init(server: String, adminKey: String, walletID: String? = nil, user: String? = nil, tor: SwiftTor? = nil, debug: DebugLevel = .zero, ssl: Bool = true) {
        if server.suffix(6) == ".onion" {
            if let tor = tor {
                self.requestType = tor
            }else {
                self.requestType = SwiftTor()
            }
            self.tor = true
        }else {
            self.connection = true
            if ssl {
                self.requestType = ClearnetRequest()
            }else {
                self.requestType = ClearnetTrustRequest()
            }
            self.tor = false
        }
        self.debug = debug
        self.server = server
        self.walletID = walletID
        self.adminKey = adminKey
        self.user = user
    }
    
    public func getWalletURL() throws -> String {
        guard let walletID = walletID else {throw "getWalletURL missing walletID"}
        guard let user = user else {throw "getWalletURL missing user"}
        return "\(server)/wallet?usr=\(user)&wal=\(walletID)"
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
        let r = try JSONDecoder().decode(Invoice.self, from: c.0)
        if debug == .all {
            print(r.paymentRequest)
        }
        return try r
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
        if debug == .all {
            print(String(data: a.0, encoding: .utf8)!)
        }
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
                throw error
            }
        }catch let error as String {
            throw error
        }catch {
            throw "Error"
        }
    }
    
    public func payInvoice(invoice: String) async throws {
        let request = getRequest(for: .invoice, method: .post, payLoad: "{\"out\": true, \"bolt11\": \"\(invoice)\"}", admin: true)
        let a = try await requestType.request(request: request)
        a.0.print()
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
        if debug != .zero {
            print(request.url!.absoluteString)
        }
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
        if debug == .all {
            print(payload)
        }
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
        if debug == .all {
            print(String(data: a.0, encoding: .utf8))
        }
        let list = try JSONDecoder().decode(LNURLPayLinks.self, from: a.0)
        return list
    }
    
    // Decode LNURL
    
    public func decodeLNURL(lnurl: String) async throws -> DecodedLNURL {
        
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
    
    public func payLNURL(lnurl: String, amount: Int) async throws {
        let decoded = try await decodeLNURL(lnurl: lnurl)
        guard decoded.kind == .pay else {throw "LNBits Error: LNURL is not a Pay Link"}
        let request = getRequest(for: .paylnurlp, method: .post, payLoad: "{\"description_hash\": \"\(decoded.descriptionHash!)\", \"callback\": \"\(decoded.callback!)\", \"amount\": \(amount * 1000), \"comment\": \"\", \"description\": \"\"}", admin: true)
        _ = try await requestType.request(request: request)
    }
    
    public struct DecodedLNURLType: Codable {
        let kind: LNURLType
    }
    
    // Create LNURL
    
    public func createLNURLWithdraw(title: String = "Withdraw", min: Int = 1, max: Int = 100000000, uses: Int = 1, waitTime: Int = 1) async throws -> LNURLWithdraw {
        let request = getRequest(for: .lnurlw, method: .post, payLoad: "{\"title\": \"\(title)\", \"min_withdrawable\": \(min), \"max_withdrawable\": \(max), \"uses\": \(uses), \"wait_time\": \(waitTime), \"is_unique\": false, \"webhook_url\": \"\"}", admin: true)
        let lnurl = try await requestType.request(request: request)
        return try JSONDecoder().decode(LNURLWithdraw.self, from: lnurl.0)
    }
    
    // List LNURLW
    
    public func getLNURLWithdraws() async throws -> [LNURLWithdraw] {
        let request = getRequest(for: .lnurlw, method: .get, admin: true)
        let lnurl = try await requestType.request(request: request)
        return try JSONDecoder().decode([LNURLWithdraw].self, from: lnurl.0)
    }
    
    // Withdraw LNURL Withdraw Link
    
    public func withdrawFromLNURLWithdraw(lnurl: String, amount: Int? = nil, memo: String? = "") async throws {
        let ln = try await decodeLNURL(lnurl: lnurl)
        guard ln.kind == .withdraw else {throw "LNBits Error: LNURL is not a withdraw link"}
        
        let invoice = try await createInvoice(sats: amount ?? ln.max!, memo: memo)
        
        let lnurlBackURL = ln.callback! + "&pr=" + invoice.paymentRequest
        
        var request = URLRequest(url: URL(string: lnurlBackURL)!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let result = try await requestType.request(request: request)

        try handleError(data: result.0)
    }
    
    public func deleteLNURLPay(id: String) async throws {
        let request = getRequest(for: .lnurlp, method: .delete, urlExtention: id, admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
    }
    
    public func deleteLNURLWithdraw(id: String) async throws {
        let request = getRequest(for: .lnurlw, method: .delete, urlExtention: id, admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
    }
    
    public func auth(callback: String) async throws {
        var request = URLRequest(url: URL(string: "\(server)/api/v1/lnurlauth")!)
        request.addValue(adminKey, forHTTPHeaderField: "X-Api-Key")
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"callback\": \"\(callback)\"}".data(using: .utf8)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
    }
    
    public func lnurlAuth(lnurl: String) async throws {
        let ln = try await decodeLNURL(lnurl: lnurl)
        
        guard ln.kind == .auth else {throw "LNBits Error: LNURL is not auth"}
        
        try await auth(callback: ln.callback!)
    }
    
    public func deleteWallet() async throws {
        guard let walletID = walletID else {throw "deleteWallet missing walletID"}
        let request = getRequest(for: .wallet, method: .delete, urlExtention: walletID, admin: true)
        let result = try await requestType.request(request: request)
//        try handleError(data: result.0)
        result.0.print()
    }
    
    // Boltz
    
    // Bitcoin --> Lightning
    
    public func createSubMarineSwap(amount: Int, refundAddress: String) async throws -> BoltzSubMarineSwap {
        guard let walletID = walletID else {throw "createSubMarineSwap missing walletID"}
        let request = getRequest(for: .boltzsms, method: .post, payLoad: "{\"wallet\": \"\(walletID)\",\"refund_address\": \"\(refundAddress)\",\"amount\": \"\(amount)\",\"feerate\": false}", admin: true)
        let result = try await requestType.request(request: request)
        result.0.print()
        try handleError(data: result.0)
        let swap = try JSONDecoder().decode(BoltzSubMarineSwap.self, from: result.0)
        return swap
    }

    public func getSubMarineSwaps() async throws -> [BoltzSubMarineSwap] {
        let request = getRequest(for: .boltzsms, method: .get)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode([BoltzSubMarineSwap].self, from: result.0)
    }

    // Lightning --> Bitcoin

    public func createReversedSubMarineSwap(amount: Int, onChainAddress: String, feeRate: Int) async throws -> BoltzReversedSubMarineSwap {
        guard let walletID = walletID else {throw "createReversedSubMarineSwap missing walletID"}
        let request = getRequest(for: .boltzrsms, method: .post, payLoad: "{\"wallet\": \"\(walletID)\",\"amount\": \"\(amount)\",\"instant_settlement\": true,\"onchain_address\": \"\(onChainAddress)\", \"feerate\": true, \"feerate_value\": \(feeRate)}", admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode(BoltzReversedSubMarineSwap.self, from: result.0)
    }

    public func getReversedSubMarineSwaps() async throws -> [BoltzReversedSubMarineSwap] {
        let request = getRequest(for: .boltzrsms, method: .get)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode([BoltzReversedSubMarineSwap].self, from: result.0)
    }

    public func refundSubMarineSwap(swapID: String) async throws -> RefundSubMarineSwap {
        let request = getRequest(for: .boltzsmsr, method: .post, payLoad: "{\"swap_id\": \"\(swapID)\"}", admin: true)
        let result = try await requestType.request(request: request)
        try handleError(data: result.0)
        return try JSONDecoder().decode(RefundSubMarineSwap.self, from: result.0)
    }
    
    // Boltcard
    
    public func createBoltCard(name: String, uid: String, txLimit: Int, dailyLimit: Int, k0: String, k1: String, k2: String, prevk0: String, prevk1: String, prevk2: String) {
    }
    
}

@available(iOS 13.0.0, macOS 13.0.0,  *)
public func loginLNBits(url: String, username: String, password: String, tor: SwiftTor?, ssl: Bool = true) async throws -> LoginWallet {
    let c = url.contains(".onion")
    var cl: RequestType = ssl ? ClearnetRequest() : ClearnetTrustRequest()
    let d: RequestType  = c ? tor ?? SwiftTor() : cl
    var request = URLRequest(url: URL(string: "\(url)\(LNBits.LNBitsRequest.login.rawValue)")!)
    print(request.url!.absoluteString)
    request.httpMethod = LNBits.HTTPMethod.post.rawValue
    request.addValue("application/json", forHTTPHeaderField: "accept")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = "{\"username\": \"\(username)\", \"password\": \"\(password)\"}".data(using: .utf8)
    print(String(data: request.httpBody!, encoding: .utf8)!)
    print(request.httpMethod!)
    let a = try await d.request(request: request)
    let login = try? JSONDecoder().decode(Login.self, from: a.0)
    guard let login = login else {
        let error = String(data: a.0, encoding: .utf8)
        guard let error = error else {
            throw "Unknown loginLNBits Error"
        }
        throw error
    }
    var request2 = URLRequest(url: URL(string: "\(url)\(LNBits.LNBitsRequest.login.rawValue)")!)
    request2.httpMethod = LNBits.HTTPMethod.get.rawValue
    request2.addValue("application/json", forHTTPHeaderField: "accept")
    request2.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request2.addValue("cookie_access_token=\(login.access_token)", forHTTPHeaderField: "cookie")
    print(request2.allHTTPHeaderFields!)
    let b = try await d.request(request: request2)
    return try JSONDecoder().decode(LoginWallet.self, from: b.0)
}

public enum LightningType {
    case bolt11
    case lnurl
}

public func checkLightningType(input: String) -> LightningType? {
    if input.prefix(4) == "lnbc" || input.prefix(4) == "LNBC" {
        return .bolt11
    }
    if input.prefix(5) == "lnurl" || input.prefix(5) == "LNURL" {
        return .lnurl
    }
    return nil
}


// --------------------------------- Models ------------------------------------


public struct LoginWallet: Codable {
    public let id, email, username: String
    public let extensions: [String]
    public let wallets: [Wallet]
    public let admin, super_user, has_password: Bool
    public let config: Config
//    let createdAt, updatedAt: JSONNull?
    
    public struct Config: Codable {
        public let email_verified: Bool
//        let firstName, lastName, displayName, picture: JSONNull?
        public let provider: String
    }
    
    public struct Wallet: Codable {
        public let id, name, user, adminkey: String
        public let inkey: String
//        let currency: JSONNull?
        public let balance_msat: Int
        public let deleted: Bool
        public let created_at, updated_at: Int
    }
}



public struct Login: Codable {
    public let access_token, token_type: String
}


public struct RefundSubMarineSwap: Codable, Hashable {
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


public struct BoltzReversedSubMarineSwap: Codable, Hashable, Identifiable {
    public let id, wallet: String
    public let amount: Int
    public let onchainAddress: String
    public let instantSettlement: Bool
    public let time: Int
    public let status, boltzID, preimage, claimPrivkey: String
    public let lockupAddress, invoice: String
    public let onchainAmount, timeoutBlockHeight: Int
    public let redeemScript: String
    
    public static let demo = BoltzReversedSubMarineSwap(id: "id", wallet: "wallet", amount: 21, onchainAddress: "onchainAddress", instantSettlement: true, time: 21, status: "status", boltzID: "boltzID", preimage: "preimage", claimPrivkey: "claimPrivkey", lockupAddress: "lockupAddress", invoice: "invoice", onchainAmount: 21, timeoutBlockHeight: 21, redeemScript: "redeemScript")

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

public struct BoltzSubMarineSwap: Codable, Hashable, Identifiable {
    public let id, wallet: String
    public let amount: Int
    public let paymentHash: String
    public let time: Int
    public let status, refundPrivkey, refundAddress, boltzID: String
    public let expectedAmount, timeoutBlockHeight: Int
    public let address, bip21, redeemScript: String
    
    public static let demo = BoltzSubMarineSwap(id: "id", wallet: "wallet", amount: 21, paymentHash: "paymentHash", time: 21, status: "status", refundPrivkey: "refundPrivkey", refundAddress: "refundAddress", boltzID: "boltzID", expectedAmount: 21, timeoutBlockHeight: 21, address: "address", bip21: "bip21", redeemScript: "redeemScript")

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

public struct LNURLWithdraw: Codable, Hashable, Identifiable {
    
    public let id, wallet, title: String
    public let minWithdrawable, maxWithdrawable, uses, waitTime: Int
    public let isUnique: Bool
    public let uniqueHash, k1: String
    public let openTime, used: Int
    public let usescsv: String
    public let number: Int
    public let webhookURL: String
    public let lnurl: String
    
    public static let demo = LNURLWithdraw(id: "id", wallet: "wallet", title: "title", minWithdrawable: 1, maxWithdrawable: 21, uses: 1, waitTime: 1, isUnique: true, uniqueHash: "uniqueHash", k1: "k1", openTime: 1, used: 1, usescsv: "usescsv", number: 1, webhookURL: "webhookURL", lnurl: "lnurl")

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

public struct DecodedLNURLP: Codable, Hashable {
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

public struct DecodedLNURLW: Codable, Hashable {
    public let domain: String
    public let tag: String
    public let callback: String
    public let k1: String
    public let minWithdrawable, maxWithdrawable: Int
    public let defaultDescription: String
    public let kind: LNURLType
    public let fixed: Bool
}

public struct DecodedLNURLAuth: Codable, Hashable {
    public let domain: String
    public let kind: LNURLType
    public let callback: String
    public let pubkey: String
}

public struct DecodedLNURL: Codable, Hashable {
    public let lnurl: String
    public let kind: LNURLType
    public let min, max: Int?
    public let description: String?
    public let domain: String
    public let callback: String?
    public let descriptionHash: String?
    
    public static let demo = DecodedLNURL(lnurl: "lnurl", kind: .pay, domain: "", callback: "")
    
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

public struct LNURLPayLink: Codable, Hashable {
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
    
    public static let demo = Invoice(paymentHash: "", paymentRequest: "", checkingID: "")
}

public struct LNBitsError: Codable {
    public let detail: String?
}

public struct CheckPaid: Codable {
    public let paid: Bool
    public let preimage: String
}

struct InvoicePaid: Codable, Hashable {
    public let paymentHash, checkingID: String

    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case checkingID = "checking_id"
    }
}

public struct DecodedInvoice: Codable, Hashable {
    public let currency: String?
    public let amount_msat: Int
    public let date: Int
    public let signature: String?
    public let payment_hash: String
    public let payment_secret: String?
    public let secret: String?
    public let description: String?
    public let expiry: Int
//    let features: PaymentFeatures
    public let min_final_cltv_expiry: Int
    public let payee: String
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

public struct LNBitsTransaction: Codable, Hashable {
    public let checking_id: String
    public let pending: Bool
    public var amount: Int
    public let fee: Int
    public let memo: String
    public let time: Int
    public let bolt11, preimage, payment_hash: String
    public let expiry: Int
    public let wallet_id: String
    
    static public let demo = LNBitsTransaction(checking_id: "checking_id", pending: false, amount: 1, fee: 1, memo: "memo", time: 0, bolt11: "bolt11", preimage: "preimage", payment_hash: "payment_hash", expiry: 0, wallet_id: "wallet_id")
}

public typealias LNBitsTransactions = [LNBitsTransaction]

public struct LNBitsKeys: Codable, Hashable {
    let adminkey: String
    let balance_msat: Int
    let id: String
    let inkey: String
    let name: String
    let user: String
}

extension String: Error {
    
}

@available(iOS 13.0.0, macOS 13.0.0, *)
public func LNBitsURL(input: String, tor: SwiftTor? = nil, ssl: Bool = true) async throws -> LNBits {
    guard let url = URL(string: input) else {throw "Not a URL"}
    let serverURL = convertToServer(input)
    let c = serverURL.suffix(6) == ".onion"
    var cl: RequestType = ssl ? ClearnetRequest() : ClearnetTrustRequest()
    let d: RequestType  = c ? tor ?? SwiftTor() : cl
    print(url.absoluteString)
    let e = try await d.request(request: URLRequest(url: url))
    print(String(data: e.0, encoding: .utf8)!)
    let keys = try lnbitsHTMLToKeys(input: e.0)
    return LNBits(server: serverURL, adminKey: keys.adminkey, walletID: keys.id, user: keys.user, tor: tor, ssl: ssl)
}

func lnbitsHTMLToKeys(input: Data) throws -> LNBitsKeys {
    guard let f = String(data: input, encoding: .utf8) else {throw "Request result is not a String"}
    guard let rangeStart = f.range(of: "window.wallet = ") else {throw "Not found window.wallet = "}
    guard let rangeEnd = f.range(of: ";", range: rangeStart.upperBound..<f.endIndex) else {throw "Not found ;"}
    guard let a = String(f[rangeStart.upperBound..<rangeEnd.lowerBound]).data(using: .utf8) else {throw "Not found lower and upper Bound"}
    guard let b = try? JSONDecoder().decode(LNBitsKeys.self, from: a) else {throw "Error Decoding"}
    return b
}

func convertToServer(_ link: String) -> String {
    var l = ""
    if link.contains("/wallet") {
        if let range = link.range(of: "/wallet") {
            l = String(link.prefix(upTo: range.lowerBound))
        }else {
            l = link
        }
    }else {
        l = link
    }
    return l
}

@available(iOS 13.0.0, macOS 13.0.0, *)
public func getNewLNBitsWallet(server: String, tor: SwiftTor? = nil) async throws -> LNBits {
    let c = server.suffix(6) == ".onion"
    let clearURL = convertToServer(server)
    let serverURL = "\(clearURL)/wallet"
    guard let url = URL(string: serverURL) else {throw "Not a URL"}
    let d: RequestType  = c ? tor ?? SwiftTor() : ClearnetRequest()
    let e = try await d.request(request: URLRequest(url: url))
    let keys = try lnbitsHTMLToKeys(input: e.0)
    return LNBits(server: clearURL, adminKey: keys.adminkey, walletID: keys.id, user: keys.user, tor: tor)
}

@available(iOS 13.0.0, macOS 13.0.0, *)
public func getDemoLNBits() async throws -> LNBits {
    let serverURL = "https://legend.lnbits.com/wallet"
    guard let url = URL(string: serverURL) else {throw "Not a URL"}
    let d = ClearnetRequest()
    let e = try await d.request(request: URLRequest(url: url))
    let keys = try lnbitsHTMLToKeys(input: e.0)
    return LNBits(server: "https://legend.lnbits.com", adminKey: keys.adminkey, walletID: keys.id, tor: nil)
}
