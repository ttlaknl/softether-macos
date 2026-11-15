// ServerConfigView.swift
// SoftEther Server Profile & Node Manager with Edit and Delete Capabilities

import SwiftUI

struct ServerConfigView: View {
    @EnvironmentObject var engine: SoftEtherEngine
    @State private var showingSheet = false
    @State private var editingConfig: VPNServerConfig? = nil
    @State private var isPasswordVisible: Bool = false
    
    // Form Input State
    @State private var nodeName = ""
    @State private var nodeHost = ""
    @State private var nodePort = "443"
    @State private var nodeHub = "VPNGATE"
    @State private var nodeUsername = "vpn"
    @State private var nodePassword = "vpn"
    @State private var hostValidationError = ""
    @State private var portValidationError = ""
    
    private let accentCyan = Color(red: 0.0, green: 0.83, blue: 1.0)
    private let accentRed = Color(red: 1.0, green: 0.35, blue: 0.35)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("服务器节点管理")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("管理、新建、编辑与删除 SoftEther VPN 虚拟 Hub 节点")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                
                Button(action: openAddModal) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("新增节点")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accentCyan)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            #if os(iOS)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            #else
            .padding(.horizontal, 24)
            .padding(.top, 24)
            #endif
            
            // Server Config List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(engine.configs) { config in
                        serverRow(config: config)
                    }
                }
                #if os(iOS)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                #else
                .padding(.horizontal, 24)
                #endif
            }
        }
        .sheet(isPresented: $showingSheet) {
            editorSheetModal
        }
    }
    
    // MARK: - Server Node Row Item
    private func serverRow(config: VPNServerConfig) -> some View {
        let isSelected = engine.currentConfig?.id == config.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentCyan.opacity(0.2) : Color.white.opacity(0.05))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "server.rack")
                        .foregroundColor(isSelected ? accentCyan : .white.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(config.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        if isSelected {
                            Text("当前使用")
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentCyan.opacity(0.2))
                                .foregroundColor(accentCyan)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("\(config.host):\(config.port) • Hub: \(config.hub) • User: \(config.username)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
                
                #if os(macOS)
                Spacer()
                serverRowActions(config: config, isSelected: isSelected)
                #endif
            }
            
            #if os(iOS)
            HStack {
                Spacer()
                serverRowActions(config: config, isSelected: isSelected)
            }
            #endif
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? accentCyan.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func serverRowActions(config: VPNServerConfig, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            // Select Button
            Button(action: {
                for idx in engine.configs.indices {
                    engine.configs[idx].isSelected = (engine.configs[idx].id == config.id)
                }
                engine.currentConfig = config
                engine.saveConfigs()
                engine.appendLog("[Config] 切换当前活动节点至: \(config.name) (\(config.host))")
            }) {
                Text(isSelected ? "已激活" : "选择")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? accentCyan.opacity(0.15) : Color.white.opacity(0.06))
                    .foregroundColor(isSelected ? accentCyan : .white.opacity(0.8))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Edit Button
            Button(action: { openEditModal(config: config) }) {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                    Text("编辑")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white.opacity(0.9))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Delete Button
            Button(action: { deleteConfig(config: config) }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(accentRed.opacity(0.9))
                    .padding(8)
                    .background(accentRed.opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Edit & Add Modal Dialog Sheet
    private var editorSheetModal: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(editingConfig == nil ? "新增 SoftEther 节点配置文件" : "编辑节点参数")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 14) {
                    inputField(title: "节点名称", placeholder: "例如: 默认服务器 (154.13.4.209)", text: $nodeName)
                    inputField(title: "服务器主机 (Host/IP)", placeholder: "154.13.4.209", text: $nodeHost)
                    if !hostValidationError.isEmpty {
                        Text(hostValidationError)
                            .font(.caption)
                            .foregroundColor(accentRed)
                    }
                    inputField(title: "服务端口 (Port)", placeholder: "992", text: $nodePort, isNumeric: true)
                    if !portValidationError.isEmpty {
                        Text(portValidationError)
                            .font(.caption)
                            .foregroundColor(accentRed)
                    }
                    inputField(title: "虚拟 Hub 名称", placeholder: "VPN", text: $nodeHub)
                    inputField(title: "验证用户名", placeholder: "ios", text: $nodeUsername)
                    
                    // Password Field with Visibility Toggle
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("验证密码")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Button(action: { isPasswordVisible.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    Text(isPasswordVisible ? "隐藏密码" : "显示密码")
                                }
                                .font(.system(size: 11))
                                .foregroundColor(accentCyan)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if isPasswordVisible {
                            TextField("输入密码", text: $nodePassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                #if os(iOS)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                #endif
                        } else {
                            SecureField("输入密码", text: $nodePassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
                
                if !isFormValid {
                    let trimmedH = nodeHost.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedP = nodePort.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedH.isEmpty {
                        Text("• 请输入服务器主机地址 (Host/IP)")
                            .font(.caption)
                            .foregroundColor(accentRed)
                    } else if Int(trimmedP) == nil || Int(trimmedP)! <= 0 || Int(trimmedP)! > 65535 {
                        Text("• 端口号必须是 1 到 65535 之间的有效数字")
                            .font(.caption)
                            .foregroundColor(accentRed)
                    }
                }
                
                HStack {
                    Button("取消") { showingSheet = false }
                        .foregroundColor(.white.opacity(0.6))
                        .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Button(action: saveConfig) {
                        Text(editingConfig == nil ? "保存并添加" : "保存更新")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(isFormValid ? accentCyan : accentCyan.opacity(0.3))
                            .foregroundColor(.black)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isFormValid)
                }
                .padding(.top, 12)
            }
            .padding(24)
        }
        #if os(macOS)
        .frame(width: 440)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .background(Color(red: 0.1, green: 0.12, blue: 0.18))
    }
    
    private func inputField(title: String, placeholder: String, text: Binding<String>, isSecure: Bool = false, isNumeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                #if os(iOS)
                TextField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(isNumeric ? .numbersAndPunctuation : .default)
                #else
                TextField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                #endif
            }
        }
    }
    
    // MARK: - Validation
    private var isFormValid: Bool {
        let trimmedHost = nodeHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return false }
        let trimmedPort = nodePort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmedPort), port > 0, port <= 65535 else { return false }
        return true
    }
    
    // MARK: - Actions
    private func openAddModal() {
        editingConfig = nil
        isPasswordVisible = false
        nodeName = ""
        nodeHost = ""
        nodePort = "992"
        nodeHub = "VPN"
        nodeUsername = "ios"
        nodePassword = ""
        hostValidationError = ""
        portValidationError = ""
        showingSheet = true
    }
    
    private func openEditModal(config: VPNServerConfig) {
        editingConfig = config
        isPasswordVisible = false
        nodeName = config.name
        nodeHost = config.host
        nodePort = "\(config.port)"
        nodeHub = config.hub
        nodeUsername = config.username
        nodePassword = config.password
        hostValidationError = ""
        portValidationError = ""
        showingSheet = true
    }
    
    private func saveConfig() {
        // Validate inputs
        hostValidationError = ""
        portValidationError = ""
        
        let trimmedHost = nodeHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.isEmpty {
            hostValidationError = "服务器地址不能为空"
            return
        }
        
        let trimmedPort = nodePort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portInt = Int(trimmedPort), portInt > 0, portInt <= 65535 else {
            portValidationError = "端口号必须在 1-65535 之间"
            return
        }
        
        let rawName = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = rawName.isEmpty ? trimmedHost : rawName
        let trimmedHub = nodeHub.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = nodeUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalHub = trimmedHub.isEmpty ? "VPN" : trimmedHub
        let finalUser = trimmedUser.isEmpty ? "vpn" : trimmedUser
        
        if let editing = editingConfig {
            // Update existing item
            if let index = engine.configs.firstIndex(where: { $0.id == editing.id }) {
                engine.configs[index].name = finalName
                engine.configs[index].host = trimmedHost
                engine.configs[index].port = portInt
                engine.configs[index].hub = finalHub
                engine.configs[index].username = finalUser
                engine.configs[index].password = nodePassword

                if engine.currentConfig?.id == editing.id {
                    engine.currentConfig = engine.configs[index]
                }
                engine.appendLog("[Config] 更新节点: \(finalName) (\(trimmedHost):\(portInt), User: \(finalUser))")
            }
        } else {
            // If user typed the same host/port/hub as an existing node, update it!
            if let matchIndex = engine.configs.firstIndex(where: { $0.host == trimmedHost && $0.port == portInt && $0.hub.caseInsensitiveCompare(finalHub) == .orderedSame }) {
                engine.configs[matchIndex].name = finalName
                engine.configs[matchIndex].username = finalUser
                engine.configs[matchIndex].password = nodePassword
                for idx in engine.configs.indices {
                    engine.configs[idx].isSelected = (idx == matchIndex)
                }
                engine.currentConfig = engine.configs[matchIndex]
                engine.appendLog("[Config] 更新已有节点: \(finalName) (User: \(finalUser))")
            } else {
                for idx in engine.configs.indices {
                    engine.configs[idx].isSelected = false
                }
                let newConfig = VPNServerConfig(name: finalName, host: trimmedHost, port: portInt, hub: finalHub, username: finalUser, password: nodePassword, isSelected: true)
                engine.configs.append(newConfig)
                engine.currentConfig = newConfig
                engine.appendLog("[Config] 新增并选择节点: \(finalName)")
            }
        }
        engine.saveConfigs()

        showingSheet = false
    }

    private func deleteConfig(config: VPNServerConfig) {
        engine.configs.removeAll(where: { $0.id == config.id })
        if engine.currentConfig?.id == config.id {
            engine.currentConfig = engine.configs.first
            if let firstId = engine.configs.first?.id,
               let idx = engine.configs.firstIndex(where: { $0.id == firstId }) {
                engine.configs[idx].isSelected = true
                engine.currentConfig = engine.configs[idx]
            }
        }
        engine.appendLog("[Config] 已删除节点配置: \(config.name)")
        engine.saveConfigs()
    }
}
