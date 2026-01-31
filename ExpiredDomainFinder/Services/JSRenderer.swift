import Foundation
import WebKit

/// Renders a URL using WKWebView to execute JavaScript, then extracts the final HTML.
/// Must be called from the main actor since WKWebView requires the main thread.
@MainActor
final class JSRenderer {
    private var pool: [WKWebView] = []
    private let poolSize: Int
    private var available: [WKWebView] = []
    private var waiters: [CheckedContinuation<WKWebView, Never>] = []

    init(poolSize: Int = 3) {
        self.poolSize = poolSize
    }

    func warmUp() {
        guard pool.isEmpty else { return }
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        // Disable media loading for speed
        config.mediaTypesRequiringUserActionForPlayback = .all
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        for _ in 0..<poolSize {
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            pool.append(wv)
            available.append(wv)
        }
    }

    private func acquire() async -> WKWebView {
        if let wv = available.popLast() {
            return wv
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release(_ wv: WKWebView) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: wv)
        } else {
            available.append(wv)
        }
    }

    /// Renders the given URL with JS and returns the final HTML string.
    /// Returns nil on timeout or failure.
    func renderHTML(url: URL, timeout: TimeInterval = 10) async -> String? {
        warmUp()
        let webView = await acquire()
        defer { release(webView) }

        let request = URLRequest(url: url, timeoutInterval: timeout)
        webView.load(request)

        // Wait for navigation to finish
        let loaded = await waitForLoad(webView: webView, timeout: timeout)
        guard loaded else {
            webView.stopLoading()
            return nil
        }

        // Give JS a moment to execute after DOM load
        try? await Task.sleep(for: .milliseconds(1500))

        // Extract rendered HTML
        let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
        return html
    }

    private func waitForLoad(webView: WKWebView, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        // Poll isLoading
        while webView.isLoading {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    func shutdown() {
        for wv in pool {
            wv.stopLoading()
        }
        pool.removeAll()
        available.removeAll()
    }
}
