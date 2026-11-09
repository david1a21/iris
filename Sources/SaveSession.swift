import Foundation

/// 页面把成品的 Blob 切成小块送过来，这里按块顺序落盘，避免大文件一次性进内存。
final class SaveSession {

    let mime: String
    private let url: URL
    private var handle: FileHandle?

    var fileURL: URL { url }

    init(name: String, mime: String) {
        self.mime = mime

        let dir = SaveSession.dir()
        var target = dir.appendingPathComponent(SaveSession.sanitize(name))
        if FileManager.default.fileExists(atPath: target.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            target = dir.appendingPathComponent(SaveSession.sanitize(SaveSession.stamped(name, stamp)))
        }
        url = target

        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            _ = fm.createFile(atPath: target.path, contents: nil, attributes: nil)
        }
        handle = try? FileHandle(forWritingTo: target)
    }

    func append(base64: String) {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return }
        try? handle?.write(contentsOf: data)
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    static func dir() -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Iris", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 文件名里不能有路径分隔符，页面给的导出名可能带空格和中文，只挡危险字符。
    static func sanitize(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = raw.components(separatedBy: bad).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Iris_\(Int(Date().timeIntervalSince1970))" : trimmed
    }

    static func stamped(_ name: String, _ stamp: Int) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        return ext.isEmpty ? "\(base)_\(stamp)" : "\(base)_\(stamp).\(ext)"
    }
}
