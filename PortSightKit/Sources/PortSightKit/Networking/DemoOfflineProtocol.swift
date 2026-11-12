import Foundation
// Explicitly blocks legacy HTTP routes in the visual prototype. Relay requests (RelayAPI, marked) are the one
// exception: server pairing, push registration and the relay reads go to the paired Mac mini over HTTPS.
public final class DemoOfflineProtocol: URLProtocol, @unchecked Sendable {
    public override class func canInit(with request: URLRequest) -> Bool {
        // Icons (SymbolLogoStore, logo.dev) are let through too.
        DemoPortfolioData.enabled && !RelayAPI.isRelayRequest(request) && !SymbolLogoStore.isLogoRequest(request)
    }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    public override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    public override func stopLoading() {}
}
