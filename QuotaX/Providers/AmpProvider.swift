import Foundation

// MARK: - Amp Provider
/// 通过本地 `amp usage` 命令获取额度信息
/// 自动检测：本地安装了 amp CLI 即可
final class AmpProvider: QuotaProvider {
    let type: ProviderType = .amp

    private static let keychainKey = "amp_api_key"

    var isConfigured: Bool { ampPath() != nil }

    func configure(apiKey: String) throws {
        try KeychainService.save(key: Self.keychainKey, value: apiKey)
    }

    func removeConfiguration() throws {
        KeychainService.delete(key: Self.keychainKey)
    }

    func fetchQuota() async throws -> QuotaInfo {
        guard let path = ampPath() else {
            throw ProviderError.notConfigured
        }
        let output = try await runAmpUsage(at: path)
        return try parse(output)
    }

    // MARK: - 查找 amp 可执行文件

    private func ampPath() -> String? {
        let candidates = [
            "/usr/local/bin/amp",
            "/opt/homebrew/bin/amp",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/amp").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - 执行 amp usage

    private func runAmpUsage(at path: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["usage"]

                var env = ProcessInfo.processInfo.environment
                env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                        continuation.resume(throwing: ProviderError.invalidResponse)
                        return
                    }
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: ProviderError.networkError(error))
                }
            }
        }
    }

    // MARK: - 解析 amp usage 输出
    /// 格式示例：
    /// Amp Free: 61% remaining today (resets daily) - https://...
    /// Individual credits: $0 remaining - https://...

    private func parse(_ output: String) throws -> QuotaInfo {
        let lines = output.components(separatedBy: "\n")

        // 匹配 "XX% remaining" 模式
        var percentage: Double?
        var resetDaily = false

        for line in lines {
            if let range = line.range(of: #"(\d+)%\s+remaining"#, options: .regularExpression) {
                let match = line[range]
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    percentage = Double(match[numRange])
                }
                resetDaily = line.contains("resets daily")
                break
            }
        }

        guard let pct = percentage else {
            throw ProviderError.invalidResponse
        }

        // 每日重置 → 今日剩余到午夜
        var resetDate: Date?
        if resetDaily {
            let calendar = Calendar.current
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) {
                resetDate = tomorrow
            }
        }

        return QuotaInfo(
            id: UUID(),
            providerType: .amp,
            limit: 100,
            used: 100 - pct,
            remaining: pct,
            remainingPercentage: pct / 100.0,
            resetDate: resetDate,
            lastUpdated: Date(),
            unit: .percentage
        )
    }
}
