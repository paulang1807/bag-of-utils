import Cocoa
import WebKit


class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var bridgeHandler: BridgeHandler!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Define initial window size and style
        let windowRect = NSRect(x: 0, y: 0, width: 950, height: 650)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Bag of Utils"
        window.minSize = NSSize(width: 850, height: 550)
        window.center()
        
        // Hide window title bar for premium borderless look
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Enable macOS system-wide vibrancy (frosted glass)
        let visualEffect = NSVisualEffectView(frame: windowRect)
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(visualEffect)

        // Webview Configuration & JS-Swift bridge registration
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        bridgeHandler = BridgeHandler()
        contentController.add(bridgeHandler, name: "bridge")
        config.userContentController = contentController
        
        // Enable local file access, CORS, and Developer Tools in WebView
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Set up transparent WKWebView
        webView = WKWebView(frame: windowRect, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground") // For macOS WebView transparency
        
        
        bridgeHandler.webView = webView
        visualEffect.addSubview(webView)
        
        // Load local index.html from bundle Resources
        if let resourceURL = Bundle.main.resourceURL {
            let webURL = resourceURL.appendingPathComponent("web/index.html")
            webView.loadFileURL(webURL, allowingReadAccessTo: resourceURL)
        } else {
            print("Failed to find main resource URL")
        }
        
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
        
        setupMainMenu()
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Bag of Utils", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Bag of Utils", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Bag of Utils", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // Edit Menu (Enables standard Cmd+C, Cmd+V, Cmd+X, Cmd+A, Cmd+Z shortcuts in WKWebView)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

class BridgeHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let callbackId = body["callbackId"] as? String else {
            return
        }
        
        switch action {
        case "selectDirectory":
            handleSelectDirectory(callbackId: callbackId)
        case "readDirectory":
            if let path = body["path"] as? String {
                handleReadDirectory(path: path, callbackId: callbackId)
            } else {
                sendResponse(callbackId: callbackId, data: nil, error: "Missing directory path parameter")
            }
        case "executeRename":
            if let directory = body["directory"] as? String,
               let renames = body["renames"] as? [[String: String]] {
                handleExecuteRename(directory: directory, renames: renames, callbackId: callbackId)
            } else {
                sendResponse(callbackId: callbackId, data: nil, error: "Missing parameters for renaming operation")
            }
        case "openInFinder":
            if let path = body["path"] as? String {
                handleOpenInFinder(path: path, callbackId: callbackId)
            } else {
                sendResponse(callbackId: callbackId, data: nil, error: "Missing path parameter")
            }
        case "selectFiles":
            handleSelectFiles(callbackId: callbackId)
        case "checkTools":
            sendResponse(callbackId: callbackId, data: Tools.status(), error: nil)
        case "executeConversion":
            if let items = body["items"] as? [[String: String]] {
                handleExecuteConversion(items: items, callbackId: callbackId)
            } else {
                sendResponse(callbackId: callbackId, data: nil, error: "Missing parameters for conversion operation")
            }
        case "saveFilePicker":
            let defaultName = body["defaultName"] as? String ?? "webpage.pdf"
            handleSaveFilePicker(defaultName: defaultName, callbackId: callbackId)
        case "fetchWebpage":
            if let urlString = body["url"] as? String {
                handleFetchWebpage(urlString: urlString, callbackId: callbackId)
            } else {
                sendResponse(callbackId: callbackId, data: nil, error: "Missing url parameter")
            }
        case "generateWebpagePDF":
            if let html = body["html"] as? String,
               let targetPath = body["targetPath"] as? String {
                let baseURL = body["baseURL"] as? String
                handleGenerateWebpagePDF(html: html, targetPath: targetPath, baseURL: baseURL, callbackId: callbackId)
            } else {
                sendResponse(callbackId: callbackId, data: nil, error: "Missing parameters for PDF generation")
            }
        case "readClipboard":
            let pasteboard = NSPasteboard.general
            let string = pasteboard.string(forType: .string) ?? ""
            sendResponse(callbackId: callbackId, data: string, error: nil)
        default:
            sendResponse(callbackId: callbackId, data: nil, error: "Unsupported action: \(action)")
        }
    }
    
    private func sendResponse(callbackId: String, data: Any?, error: String?) {
        var response: [String: Any] = [:]
        if let data = data {
            response["data"] = data
        }
        if let error = error {
            response["error"] = error
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to serialize IPC bridge response")
            return
        }
        
        // Execute JS callback resolution on the main thread
        let jsScript = "window.Bridge.resolve('\(callbackId)', \(jsonString));"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(jsScript, completionHandler: { (_, error) in
                if let error = error {
                    print("Error resolving JS callback: \(error.localizedDescription)")
                }
            })
        }
    }
    
    private func handleSelectDirectory(callbackId: String) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.title = "Choose Folder for Renaming"
            panel.prompt = "Choose"
            
            if panel.runModal() == .OK, let url = panel.url {
                self.sendResponse(callbackId: callbackId, data: url.path, error: nil)
            } else {
                self.sendResponse(callbackId: callbackId, data: nil, error: "Cancelled")
            }
        }
    }
    
    private func handleReadDirectory(path: String, callbackId: String) {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            sendResponse(callbackId: callbackId, data: nil, error: "Directory path does not exist or is not a directory")
            return
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            var filesList: [[String: Any]] = []
            
            for item in contents {
                if item.hasPrefix(".") { continue } // Filter hidden files like .DS_Store
                
                let fullPath = (path as NSString).appendingPathComponent(item)
                var size: Int64 = 0
                var isSubDir = false
                
                if let attributes = try? fileManager.attributesOfItem(atPath: fullPath) {
                    size = attributes[.size] as? Int64 ?? 0
                    isSubDir = (attributes[.type] as? FileAttributeType) == .typeDirectory
                }
                
                filesList.append([
                    "name": item,
                    "size": size,
                    "isDirectory": isSubDir
                ])
            }
            
            sendResponse(callbackId: callbackId, data: filesList, error: nil)
        } catch {
            sendResponse(callbackId: callbackId, data: nil, error: error.localizedDescription)
        }
    }
    
    private func handleExecuteRename(directory: String, renames: [[String: String]], callbackId: String) {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)
        
        var renamedCount = 0
        var failures: [String] = []
        
        for pair in renames {
            guard let oldName = pair["oldName"], let newName = pair["newName"] else {
                continue
            }
            
            let oldURL = directoryURL.appendingPathComponent(oldName)
            let newURL = directoryURL.appendingPathComponent(newName)
            
            do {
                try fileManager.moveItem(at: oldURL, to: newURL)
                renamedCount += 1
            } catch {
                failures.append("\(oldName): \(error.localizedDescription)")
            }
        }
        
        if failures.isEmpty {
            sendResponse(callbackId: callbackId, data: ["renamedCount": renamedCount], error: nil)
        } else {
            let errorMsg = failures.joined(separator: " | ")
            sendResponse(callbackId: callbackId, data: ["renamedCount": renamedCount], error: errorMsg)
        }
    }
    
    private func handleSelectFiles(callbackId: String) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = true
            panel.title = "Choose Documents to Convert"
            panel.prompt = "Choose"
            
            guard panel.runModal() == .OK else {
                self.sendResponse(callbackId: callbackId, data: nil, error: "Cancelled")
                return
            }
            let files: [[String: Any]] = panel.urls.map { url in
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                return [
                    "name": url.lastPathComponent,
                    "path": url.path,
                    "directory": url.deletingLastPathComponent().path,
                    "size": attrs?[.size] as? Int64 ?? 0,
                    "isDirectory": false
                ]
            }
            self.sendResponse(callbackId: callbackId, data: files, error: nil)
        }
    }
    
    private func handleExecuteConversion(items: [[String: String]], callbackId: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let engine = ConversionEngine()
            var results: [[String: Any]] = []
            var convertedCount = 0
            
            for item in items {
                guard let source = item["sourcePath"], let target = item["targetPath"],
                      let format = item["targetFormat"] else { continue }
                do {
                    let targetURL = URL(fileURLWithPath: target)
                    try FileManager.default.createDirectory(
                        at: targetURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try engine.convert(source: URL(fileURLWithPath: source), target: targetURL, targetFormat: format)
                    convertedCount += 1
                    results.append(["sourcePath": source, "ok": true])
                } catch {
                    results.append(["sourcePath": source, "ok": false, "error": error.localizedDescription])
                }
            }
            self.sendResponse(callbackId: callbackId,
                              data: ["convertedCount": convertedCount, "results": results],
                              error: nil)
        }
    }
    
    private func handleOpenInFinder(path: String, callbackId: String) {
        DispatchQueue.main.async {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
            self.sendResponse(callbackId: callbackId, data: true, error: nil)
        }
    }
    
    private var activeRenderers: [UUID: WebPDFRenderer] = [:]
    
    private func handleSaveFilePicker(defaultName: String, callbackId: String) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.title = "Save Webpage as PDF"
            panel.prompt = "Save PDF"
            panel.canCreateDirectories = true
            panel.allowedFileTypes = ["pdf"]
            panel.nameFieldStringValue = defaultName.hasSuffix(".pdf") ? defaultName : "\(defaultName).pdf"
            
            if panel.runModal() == .OK, let url = panel.url {
                self.sendResponse(callbackId: callbackId, data: url.path, error: nil)
            } else {
                self.sendResponse(callbackId: callbackId, data: nil, error: "Cancelled")
            }
        }
    }
    
    private func handleFetchWebpage(urlString: String, callbackId: String) {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            sendResponse(callbackId: callbackId, data: nil, error: "Invalid URL. Please enter a valid http or https address.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { [weak self] (data, response, error) in
            guard let self = self else { return }
            if let error = error {
                self.sendResponse(callbackId: callbackId, data: nil, error: error.localizedDescription)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.sendResponse(callbackId: callbackId, data: nil, error: "Invalid response from server")
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                self.sendResponse(callbackId: callbackId, data: nil, error: "HTTP \(httpResponse.statusCode): Unable to fetch page.")
                return
            }

            guard let data = data else {
                self.sendResponse(callbackId: callbackId, data: nil, error: "No data received from webpage")
                return
            }

            let htmlString = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)

            let finalURL = httpResponse.url?.absoluteString ?? urlString
            self.sendResponse(callbackId: callbackId, data: [
                "html": htmlString,
                "url": finalURL
            ], error: nil)
        }
        task.resume()
    }
    
    private func handleGenerateWebpagePDF(html: String, targetPath: String, baseURL: String?, callbackId: String) {
        DispatchQueue.main.async {
            let id = UUID()
            let renderer = WebPDFRenderer(html: html, targetPath: targetPath, baseURLString: baseURL) { [weak self] result in
                DispatchQueue.main.async {
                    self?.activeRenderers.removeValue(forKey: id)
                    switch result {
                    case .success(let path):
                        self?.sendResponse(callbackId: callbackId, data: ["path": path], error: nil)
                    case .failure(let error):
                        self?.sendResponse(callbackId: callbackId, data: nil, error: error.localizedDescription)
                    }
                }
            }
            self.activeRenderers[id] = renderer
            renderer.start()
        }
    }
}

class WebPDFRenderer: NSObject, WKNavigationDelegate {
    let html: String
    let targetPath: String
    let baseURLString: String?
    let completion: (Result<String, Error>) -> Void
    var webView: WKWebView?
    var didFinishCalled = false
    var timeoutWorkItem: DispatchWorkItem?

    init(html: String, targetPath: String, baseURLString: String?, completion: @escaping (Result<String, Error>) -> Void) {
        self.html = html
        self.targetPath = targetPath
        self.baseURLString = baseURLString
        self.completion = completion
        super.init()
    }

    func start() {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 792, height: 1120), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.didFinishCalled else { return }
            self.didFinishCalled = true
            self.completion(.failure(ConversionError("PDF rendering timed out")))
            self.webView = nil
        }
        self.timeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 25.0, execute: timeoutItem)

        let base = baseURLString.flatMap { URL(string: $0) }
        wv.loadHTMLString(html, baseURL: base)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didFinishCalled else { return }
        didFinishCalled = true
        timeoutWorkItem?.cancel()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            let pdfConfig = WKPDFConfiguration()
            self.webView?.createPDF(configuration: pdfConfig) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    do {
                        let targetURL = URL(fileURLWithPath: self.targetPath)
                        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: targetURL, options: .atomic)
                        self.completion(.success(self.targetPath))
                    } catch {
                        self.completion(.failure(error))
                    }
                case .failure(let error):
                    self.completion(.failure(error))
                }
                self.webView = nil
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !didFinishCalled else { return }
        didFinishCalled = true
        timeoutWorkItem?.cancel()
        completion(.failure(error))
        self.webView = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !didFinishCalled else { return }
        didFinishCalled = true
        timeoutWorkItem?.cancel()
        completion(.failure(error))
        self.webView = nil
    }
}

// Start Native Cocoa Application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
