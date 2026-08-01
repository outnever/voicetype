import Foundation

/// API Key 配置文件存储（替代 Keychain）。
///
/// 用户要求：API Key 不存钥匙串，改存应用配置文件。
/// 文件位置：~/Library/Application Support/VoiceType/api-keys.json
/// （macOS 标准应用数据目录，不随项目提交 git）
///
/// 结构：
/// {
///   "providers": {
///     "deepseek": "sk-xxx",
///     "openai": "sk-xxx"
///   }
/// }
///
/// 注意：这是明文存储，仅适用于个人本机使用场景。
final class ConfigFileStore {

    /// 配置文件路径（Application Support/VoiceType/api-keys.json）
    static var configFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appending(path: "VoiceType", directoryHint: .isDirectory)
        return dir.appending(path: "api-keys.json")
    }

    private struct KeysFile: Codable {
        var providers: [String: String] = [:]
    }

    // MARK: - 读写

    /// 读取全部 API Key。
    private func readAll() -> [String: String] {
        guard let data = try? Data(contentsOf: Self.configFileURL) else { return [:] }
        guard let file = try? JSONDecoder().decode(KeysFile.self, from: data) else { return [:] }
        return file.providers
    }

    /// 写入全部 API Key（原子写：先写临时文件再替换）。
    private func writeAll(_ providers: [String: String]) throws {
        let file = KeysFile(providers: providers)
        let data = try JSONEncoder().encode(file)

        let dir = Self.configFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 原子写入，避免写一半崩溃损坏文件
        let tempURL = Self.configFileURL.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        try FileManager.default.replaceItemAt(Self.configFileURL, withItemAt: tempURL)
    }

    // MARK: - 公共 API

    /// 保存指定供应商的 API Key。
    func store(key: String, value: String) throws {
        var all = readAll()
        all[key] = value
        try writeAll(all)
        Log.settings.info("API Key 已保存到配置文件: \(key)")
    }

    /// 读取指定供应商的 API Key。
    func retrieve(key: String) -> String? {
        readAll()[key]
    }

    /// 安全读取——不存在返回 nil。
    func retrieveQuiet(key: String) -> String? {
        retrieve(key: key)
    }

    /// 检查指定供应商是否已有 API Key。
    func exists(key: String) -> Bool {
        readAll()[key] != nil
    }

    /// 删除指定供应商的 API Key。
    func delete(key: String) throws {
        var all = readAll()
        all.removeValue(forKey: key)
        try writeAll(all)
        Log.settings.info("API Key 已从配置文件删除: \(key)")
    }

    /// 脱敏显示（•••• + 后 4 位）。
    func obfuscatedValue(for key: String) -> String {
        guard let full = retrieve(key: key), full.count > 4 else {
            return "••••"
        }
        return "••••" + full.suffix(4)
    }
}
