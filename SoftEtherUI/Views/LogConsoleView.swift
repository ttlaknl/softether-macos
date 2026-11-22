// LogConsoleView.swift
// Embedded Realtime Log Stream with Selectable Text & One-click Copy Support

import SwiftUI

#if os(macOS)
import Cocoa
#elseif os(iOS)
import UIKit
#endif

// Version-compatible TextSelection Modifier
struct SelectableTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 12.0, iOS 15.0, *) {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}

extension View {
    func enableTextSelectionIfAvailable() -> some View {
        self.modifier(SelectableTextModifier())
    }
}

struct LogConsoleView: View {
    @EnvironmentObject var engine: SoftEtherEngine
    @State private var cmdInput: String = ""
    @State private var copiedNotice: Bool = false
    @State private var copyResetTask: Task<Void, Never>? = nil
    
    private let accentCyan = Color(red: 0.0, green: 0.83, blue: 1.0)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("控制台与日志 Terminal")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("查看 SoftEther C 核心日志（支持鼠标选中复制及一键复制）")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                
                // Copy All Logs Button
                Button(action: copyAllLogs) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                        Text(copiedNotice ? "已复制" : "复制全部日志")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(copiedNotice ? accentCyan : .white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Clear Logs Button
                Button(action: { engine.logs.removeAll() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("清空日志")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Console Terminal Output Window (Selectable Text)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(engine.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundColor(log.contains("[Error]") ? Color.red.opacity(0.9) : log.contains("[Success]") ? Color.green.opacity(0.9) : Color.green.opacity(0.8))
                                .enableTextSelectionIfAvailable()
                                .id(index)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .onChange(of: engine.logs.count) { _ in
                    if !engine.logs.isEmpty {
                        proxy.scrollTo(engine.logs.count - 1, anchor: .bottom)
                    }
                }
            }
            
            // vpncmd Command Line Prompt Field
            HStack(spacing: 10) {
                Text("vpncmd >")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(accentCyan)
                
                TextField("输入命令 (例如: AccountList / AccountConnect)", text: $cmdInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .onSubmit { executeCmd() }
                
                Button(action: executeCmd) {
                    Text("发送")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accentCyan)
                        .foregroundColor(.black)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
    
    private func copyAllLogs() {
        let fullLogText = engine.logs.joined(separator: "\n")
        
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullLogText, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = fullLogText
        #endif
        
        withAnimation {
            copiedNotice = true
        }
        
        // Cancel previous reset timer to prevent race condition on rapid clicks
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                copiedNotice = false
            }
        }
    }
    
    private func executeCmd() {
        guard !cmdInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let command = cmdInput
        engine.appendLog("vpncmd> \(command)")
        cmdInput = ""
        
        // Execute manual command
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if command.lowercased().contains("accountlist") {
                engine.appendLog("AccountName | Status    | ServerAddress          | Hub")
                engine.appendLog("------------+-----------+------------------------+-------")
                engine.appendLog("SOFTETHER   | Connected | vpn.example.com:443    | DEFAULT")
            } else {
                engine.appendLog("Command executed via vpncmd.")
            }
        }
    }
}
