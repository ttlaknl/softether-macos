// ServerConfigView.swift
// SoftEther Server Profile & Node Manager with Edit and Delete Capabilities

import SwiftUI

struct ServerConfigView: View {
    @EnvironmentObject var engine: SoftEtherEngine
    @State private var showingSheet = false
    @State private var editingConfig: VPNServerConfig? = nil
    
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("服务器节点管理")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("管理、新建、编辑与删除 SoftEther VPN 虚拟 Hub 节点")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                
                Button(action: openAddModal) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("新增节点")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accentCyan)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Server Config List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(engine.configs) { config in
                        serverRow(config: config)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: $showingSheet) {
            editorSheetModal
        }
    }
    
    // MARK: - Server Node Row Item
    private func serverRow(config: VPNServerConfig) -> some View {
        let isSelected = engine.currentConfig?.id == config.id
        
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isSelected ? accentCyan.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 42, height: 42)
                
                Image(systemName: "server.rack")
                    .foregroundColor(isSelected ? accentCyan : .white.opacity(0.5))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(config.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if isSelected {
                        Text("当前使用")
                            .font(.system(size: 10, weight: .bold))
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
            }
            
            Spacer()
            
            // Action Buttons (Select, Edit, Delete)
            HStack(spacing: 8) {
                // Select Button
                Button(action: {
                    engine.currentConfig = config
                    engine.appendLog("[Config] 切换当前活动节点至: \(config.name) (\(config.host))")
                }) {
                    Text(isSelected ? "已激活" : "选择")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? accentCyan.opacity(0.15) : Color.white.opacity(0.06))
                        .foregroundColor(isSelected ? accentCyan : .white.opacity(0.8))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Edit Button
                Button(action: { openEditModal(config: config) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(8)
                        .background(Color.white.opacity(0.06))
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
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? accentCyan.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Edit & Add Modal Dialog Sheet
    private var editorSheetModal: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(editingConfig == nil ? "新增 SoftEther 节点配置文件" : "编辑节点参数")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 14) {
                inputField(title: "节点名称", placeholder: "例如: 团队测试服务器", text: $nodeName)
                inputField(title: "服务器主机 (Host/IP)", placeholder: "154.13.4.209", text: $nodeHost)
                if !hostValidationError.isEmpty {
                    Text(hostValidationError)
                        .font(.caption)
                        .foregroundColor(accentRed)
                }
                inputField(title: "服务端口 (Port)", placeholder: "443", text: $nodePort)
                if !portValidationError.isEmpty {
                    Text(portValidationError)
                        .font(.caption)
                        .foregroundColor(accentRed)
                }
                inputField(title: "虚拟 Hub 名称", placeholder: "VPNGATE", text: $nodeHub)
                inputField(title: "验证用户名", placeholder: "laknl", text: $nodeUsername)
                inputField(title: "验证密码", placeholder: "输入密码", text: $nodePassword, isSecure: true)
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
        #if os(macOS)
        .frame(width: 440)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .background(Color(red: 0.1, green: 0.12, blue: 0.18))
    }
    
    private func inputField(title: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }
    
    // MARK: - Validation
    private var isFormValid: Bool {
        let trimmedHost = nodeHost.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { return false }
        guard let port = Int(nodePort), port > 0, port <= 65535 else { return false }
        return true
    }
    
    // MARK: - Actions
    private func openAddModal() {
        editingConfig = nil
        nodeName = ""
        nodeHost = ""
        nodePort = "443"
        nodeHub = "VPNGATE"
        nodeUsername = "vpn"
        nodePassword = "vpn"
        hostValidationError = ""
        portValidationError = ""
        showingSheet = true
    }
    
    private func openEditModal(config: VPNServerConfig) {
        editingConfig = config
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
        
        let trimmedHost = nodeHost.trimmingCharacters(in: .whitespaces)
        if trimmedHost.isEmpty {
            hostValidationError = "服务器地址不能为空"
            return
        }
        
        guard let portInt = Int(nodePort), portInt > 0, portInt <= 65535 else {
            portValidationError = "端口号必须在 1-65535 之间"
            return
        }
        
        let finalName = nodeName.trimmingCharacters(in: .whitespaces).isEmpty ? trimmedHost : nodeName
        
        if let editing = editingConfig {
            // Update existing item
            if let index = engine.configs.firstIndex(where: { $0.id == editing.id }) {
                engine.configs[index].name = finalName
                engine.configs[index].host = nodeHost
                engine.configs[index].port = portInt
                engine.configs[index].hub = nodeHub
                engine.configs[index].username = nodeUsername
                engine.configs[index].password = nodePassword

                if engine.currentConfig?.id == editing.id {
                    engine.currentConfig = engine.configs[index]
                }
                engine.appendLog("[Config] 更新节点: \(finalName)")
            }
        } else {
            // Create new item
            let newConfig = VPNServerConfig(name: finalName, host: nodeHost, port: portInt, hub: nodeHub, username: nodeUsername, password: nodePassword)
            engine.configs.append(newConfig)
            if engine.currentConfig == nil {
                engine.currentConfig = newConfig
            }
            engine.appendLog("[Config] 新增节点: \(finalName)")
        }
        engine.saveConfigs()

        showingSheet = false
    }

    private func deleteConfig(config: VPNServerConfig) {
        engine.configs.removeAll(where: { $0.id == config.id })
        if engine.currentConfig?.id == config.id {
            engine.currentConfig = engine.configs.first
        }
        engine.appendLog("[Config] 已删除节点配置: \(config.name)")
        engine.saveConfigs()
    }
}
