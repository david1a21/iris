import UIKit
import WebKit
import Photos

/// 只做一件事：把页面装进一个像样的容器。
/// 页面本身一份不改（Resources/index.html 与用户给的 HTML 逐字节一致），
/// 系统侧缺的东西在外壳补：保存到相册 / 分享 / 安全区 / 系统选择器放宽。
final class ShellViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {

    private let ink = UIColor(red: 8.0 / 255.0, green: 8.0 / 255.0, blue: 10.0 / 255.0, alpha: 1.0)
    private var web: WKWebView!
    private var session: SaveSession?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ink

        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = .default()                       // localStorage / 设置要能留住
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []
        conf.defaultWebpagePreferences.allowsContentJavaScript = true
        conf.allowsAirPlayForMediaPlayback = false

        let ucc = WKUserContentController()
        ucc.add(self, name: "iris")
        if let shim = Self.resourceText("iris-ios-shim", "js") {
            ucc.addUserScript(WKUserScript(source: shim,
                                           injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true))
        }
        conf.userContentController = ucc

        web = WKWebView(frame: view.bounds, configuration: conf)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.isOpaque = false
        web.backgroundColor = ink
        web.scrollView.backgroundColor = ink
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never  // 安全区交给页面里的 CSS，避免二次留白
        web.allowsLinkPreview = false
        web.navigationDelegate = self
        view.addSubview(web)

        guard let page = Bundle.main.url(forResource: "index", withExtension: "html") else { return }
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        web.frame = view.bounds
    }

    private static func resourceText(_ name: String, _ ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 页面 → 原生

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "iris",
              let body = message.body as? [String: Any],
              let op = body["op"] as? String else { return }

        switch op {
        case "begin":
            let name = (body["name"] as? String) ?? "Iris_\(Int(Date().timeIntervalSince1970))"
            let mime = (body["mime"] as? String) ?? "application/octet-stream"
            session = SaveSession(name: name, mime: mime)
        case "chunk":
            if let b64 = body["b64"] as? String { session?.append(base64: b64) }
        case "end":
            finish()
        default:
            break
        }
    }

    private func finish() {
        guard let s = session else { return }
        session = nil
        s.close()
        let url = s.fileURL

        let isImage = s.mime.hasPrefix("image/")
        let isVideo = s.mime.hasPrefix("video/")
        if isImage || isVideo { saveToPhotos(url, isVideo: isVideo) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        share(url)
    }

    private func saveToPhotos(_ url: URL, isVideo: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                if isVideo {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            } completionHandler: { _, _ in }
        }
    }

    private func share(_ url: URL) {
        if presentedViewController != nil { return }   // 连导多张时不叠弹面板
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(ac, animated: true)
    }

    // MARK: - 链接

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           navigationAction.navigationType == .linkActivated,
           let scheme = url.scheme, scheme == "http" || scheme == "https" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
