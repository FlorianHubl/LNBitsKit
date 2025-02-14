import XCTest
@testable import LNBitsKit

final class LNBitsKitTests: XCTestCase {
    func test() async throws {
        if #available(iOS 13.0.0, *) {
//            let lnbits = LNBits(server: "https://legend.lnbits.com", walletID: "45d1fcbb480f4c4eb670a27aa1ce08a9", adminKey: "a8700717f9f14b58ac07595734c139bf", invoiceKey: "948352def9e1483d9f8719c2f6a1fb87")
            
            let lnbits = try await getNewLNBitsWallet(server: "https://legend.lnbits.com")
            print(try! lnbits.getWalletURL())
            try await lnbits.deleteWallet()
            
//            let swap = try await lnbits.getSubMarineSwaps()
//
//            print(swap)
            
            // Check connection
                    
//                    if await lnbits.testConnection() {
//
//                        // Generating an Invoice
//
//                        let invoice = try! await lnbits.createInvoice(sats: 21, memo: "Hello :)")
//                        let paymentRequest = invoice.paymentRequest
//
//                        // Decoding an Invoice
//
//                        let decodeInvoice = try! await lnbits.decodeInvoice(invoice: "lnbc210n1pjd62g3sp5pwlfye29mk6mmsxzhj8w3cvq4va3tu2uwj2klwjqpguzhw67x38qpp5upej4ls9ytz7ard5ttq93m4ngrz6uw20tgv0jskmmvgv9y0e40wqdq2f38xy6t5wvxqzjccqpjrzjqw6lfdpjecp4d5t0gxk5khkrzfejjxyxtxg5exqsd95py6rhwwh72rpgrgqq3hcqqgqqqqlgqqqqqqgq9q9qxpqysgq9szuwpy2kd7ksk9vsgdnef9z0pdzdermcya50dd7ncgemzzlqptyukew6zd2m0ynan6shxv0s02qxvgzkapdfvps59vzx550hul6g0gp0937wp")
//                        let amount = decodeInvoice.amount
//                        let memo = decodeInvoice.description
//
//                        // Paying an Invoice
//
//                        try await lnbits.payInvoice(invoice: "lnbc210n1pjd62g3sp5pwlfye29mk6mmsxzhj8w3cvq4va3tu2uwj2klwjqpguzhw67x38qpp5upej4ls9ytz7ard5ttq93m4ngrz6uw20tgv0jskmmvgv9y0e40wqdq2f38xy6t5wvxqzjccqpjrzjqw6lfdpjecp4d5t0gxk5khkrzfejjxyxtxg5exqsd95py6rhwwh72rpgrgqq3hcqqgqqqqlgqqqqqqgq9q9qxpqysgq9szuwpy2kd7ksk9vsgdnef9z0pdzdermcya50dd7ncgemzzlqptyukew6zd2m0ynan6shxv0s02qxvgzkapdfvps59vzx550hul6g0gp0937wp")
//
//                        // Get Wallet Balance
//
//                        let balance = try await lnbits.getBalance()
//
//                        // Get Wallet Name
//
//                        let name = try await lnbits.getName()
//
//                        // Change Wallet Name
                        
            
        } else {
            // Fallback on earlier versions
        }
    }
    
    func testURL() async throws {
        let url = "https://legend.lnbits.com"
//        let l = try await LNBitsURL(input: url)
    }
    
    func testLogin() async throws {
        let a = try await loginLNBits(url: "https://legend.lnbits.com", username: "Flo", password: "btcwillwin", tor: nil)
        print(a.wallets.first!.adminkey)
    }
    
}
