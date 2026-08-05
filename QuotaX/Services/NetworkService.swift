import Foundation

// MARK: - 网络服务
/// 自定义 URLSession，信任系统证书链（含用户安装的代理/VPN 证书）
/// 解决 VPN/代理环境下 TLS 中间人解密导致的 -1200 错误
enum NetworkService {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: TLSTrustDelegate(), delegateQueue: nil)
    }()
}

// MARK: - TLS 证书信任代理
private final class TLSTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 使用系统信任策略评估（包含用户安装的 CA 证书）
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
