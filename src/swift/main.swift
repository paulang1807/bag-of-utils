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
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    
    private func handleOpenInFinder(path: String, callbackId: String) {
        DispatchQueue.main.async {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
            self.sendResponse(callbackId: callbackId, data: true, error: nil)
        }
    }
}

// Start Native Cocoa Application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
