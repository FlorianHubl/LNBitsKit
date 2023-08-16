# LNBitsKit

<img src="https://github.com/FlorianHubl/LNBitsKit/blob/main/LNBitsKit.png" width="173" height="173">

A Swift Package for interacting with LNBits.

- Add it using XCode menu **File > Swift Package > Add Package Dependency**
- Add **https://github.com/FlorianHubl/LNBitsKit** as Swift Package URL
- Click on the package
- Click Add Package and you are done

## Requirements

- iOS 13 or higher
- iPadOS 13 or higher
- macOS 10.15 or higher
- Mac Catalyst 13 or higher
- tvOS 6 or higher
- watchOS 6 or higher

## Demo

### Connecting to LNBits

```swift
let lnbits = LNBits(server: "https://legend.lnbits.com", adminKey: "145a510c4ce1496e827e1fc34934b980", invoiceKey: "a04c53fec8524ba3aa63d8385e41c288")
```

These keys are in the Api docs in your LNBits Wallet.

### Testing connection

```swift
if try? await lnbits.testConnection() {
    // connected
}else {
    // not connected
}
```

### Generating an Invoice

```swift
let invoice = try! await lnbits.createInvoice(sats: 21, memo: "Hello :)")
let paymentRequest = invoice.paymentRequest
```

### Decoding Invoice

```swift
let invoice = try! await lnbits.decodeInvoice(invoice: "lnbc210n1pjd62g3sp5pwlfye29mk6mmsxzhj8w3cvq4va3tu2uwj2klwjqpguzhw67x38qpp5upej4ls9ytz7ard5ttq93m4ngrz6uw20tgv0jskmmvgv9y0e40wqdq2f38xy6t5wvxqzjccqpjrzjqw6lfdpjecp4d5t0gxk5khkrzfejjxyxtxg5exqsd95py6rhwwh72rpgrgqq3hcqqgqqqqlgqqqqqqgq9q9qxpqysgq9szuwpy2kd7ksk9vsgdnef9z0pdzdermcya50dd7ncgemzzlqptyukew6zd2m0ynan6shxv0s02qxvgzkapdfvps59vzx550hul6g0gp0937wp")
let amount = invoice.amount
let memo = invoice.description
```

### Paying Invoice

```swift
try! await lnbits.payInvoice(invoice: "lnbc210n1pjd62g3sp5pwlfye29mk6mmsxzhj8w3cvq4va3tu2uwj2klwjqpguzhw67x38qpp5upej4ls9ytz7ard5ttq93m4ngrz6uw20tgv0jskmmvgv9y0e40wqdq2f38xy6t5wvxqzjccqpjrzjqw6lfdpjecp4d5t0gxk5khkrzfejjxyxtxg5exqsd95py6rhwwh72rpgrgqq3hcqqgqqqqlgqqqqqqgq9q9qxpqysgq9szuwpy2kd7ksk9vsgdnef9z0pdzdermcya50dd7ncgemzzlqptyukew6zd2m0ynan6shxv0s02qxvgzkapdfvps59vzx550hul6g0gp0937wp")
```

### Coming soon: Wallet Balance, Wallet Name, Change Wallet Name, LNURL…
