import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let windowSize = NSSize(width: 400, height: 200)
        let screenSize = NSScreen.main?.frame.size ?? .zero
        let rect = NSMakeRect((screenSize.width - windowSize.width) / 2,
                              (screenSize.height - windowSize.height) / 2,
                              windowSize.width, windowSize.height)
        
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "SoftEther VPN Client"
        window.makeKeyAndOrderFront(nil)
        
        let view = NSView(frame: rect)
        window.contentView = view
        
        // Add a title label
        let label = NSTextField(labelWithString: "SoftEther VPN Client Control")
        label.font = NSFont.boldSystemFont(ofSize: 16)
        label.frame = NSMakeRect(20, 140, 360, 30)
        label.alignment = .center
        view.addSubview(label)

        // Add buttons
        let startBtn = NSButton(frame: NSMakeRect(50, 80, 140, 40))
        startBtn.title = "Start VPN Client"
        startBtn.bezelStyle = .rounded
        startBtn.target = self
        startBtn.action = #selector(startVPN)
        view.addSubview(startBtn)
        
        let stopBtn = NSButton(frame: NSMakeRect(210, 80, 140, 40))
        stopBtn.title = "Stop VPN Client"
        stopBtn.bezelStyle = .rounded
        stopBtn.target = self
        stopBtn.action = #selector(stopVPN)
        view.addSubview(stopBtn)

        let cmdBtn = NSButton(frame: NSMakeRect(130, 20, 140, 40))
        cmdBtn.title = "Open vpncmd"
        cmdBtn.bezelStyle = .rounded
        cmdBtn.target = self
        cmdBtn.action = #selector(runCmd)
        view.addSubview(cmdBtn)
        
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func startVPN() {
        runCommand(cmd: "sudo ./vpnclient start")
    }
    
    @objc func stopVPN() {
        runCommand(cmd: "sudo ./vpnclient stop")
    }

    @objc func runCmd() {
        let dirPath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").path
        let script = """
        tell application "Terminal"
            do script "cd \\"\(dirPath)\\" && ./vpncmd"
            activate
        end tell
        """
        runAppleScript(script: script)
    }
    
    func runCommand(cmd: String) {
        let dirPath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").path
        let script = "do shell script \"cd \\\"\(dirPath)\\\" && \(cmd)\" with administrator privileges"
        runAppleScript(script: script)
    }

    func runAppleScript(script: String) {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                let alert = NSAlert()
                alert.messageText = "Execution Error"
                alert.informativeText = "\(err)"
                alert.runModal()
            } else {
                let alert = NSAlert()
                alert.messageText = "Success"
                alert.informativeText = "Command executed successfully."
                alert.runModal()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
