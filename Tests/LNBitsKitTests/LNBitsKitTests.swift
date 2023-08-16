import XCTest
@testable import LNBitsKit

final class LNBitsKitTests: XCTestCase {
    func testExample() throws {
        if #available(iOS 13.0.0, *) {
            let lnbits = LNBits(server: "https://legend.lnbits.com", adminKey: "145a510c4ce1496e827e1fc34934b980", invoiceKey: "a04c53fec8524ba3aa63d8385e41c288")
            try! await lnbits.payInvoice(invoice: "lnbc210n1pjd62g3sp5pwlfye29mk6mmsxzhj8w3cvq4va3tu2uwj2klwjqpguzhw67x38qpp5upej4ls9ytz7ard5ttq93m4ngrz6uw20tgv0jskmmvgv9y0e40wqdq2f38xy6t5wvxqzjccqpjrzjqw6lfdpjecp4d5t0gxk5khkrzfejjxyxtxg5exqsd95py6rhwwh72rpgrgqq3hcqqgqqqqlgqqqqqqgq9q9qxpqysgq9szuwpy2kd7ksk9vsgdnef9z0pdzdermcya50dd7ncgemzzlqptyukew6zd2m0ynan6shxv0s02qxvgzkapdfvps59vzx550hul6g0gp0937wp")
            
            
            
        } else {
            // Fallback on earlier versions
        }
    }
}
