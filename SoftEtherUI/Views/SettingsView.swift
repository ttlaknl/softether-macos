// SettingsView.swift
// Settings & System Preferences — connected to SoftEtherEngine

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: SoftEtherEngine
    
    private let accentCyan = Color(red: 0.0, green: 0.83, blue: 1.0)
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("高级首选项")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    #if os(iOS)
                    Text("针对 iPhone / iPad (ARM64) 的网络协议栈与诊断配置")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    #else
                    Text("针对 Apple Silicon (M系列 CPU) 的平台优化配置")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    #endif
                }
                
                sectionCard(title: "安全与隐蔽防护", icon: "shield.hightarget") {
                    VStack(spacing: 16) {
                        Toggle(isOn: $engine.settings.killSwitchEnabled) {
                            settingLabel(title: "全局 Kill Switch 断网保护", description: "VPN 意外中断时立即暂停所有网络通信，防止 IP 泄漏")
                        }
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        Toggle(isOn: $engine.settings.dnsLeakProtection) {
                            settingLabel(title: "DNS 泄漏防护与 SecureDNS", description: "强制通过 SoftEther 虚拟网卡接口解析 DNS 域名")
                        }
                    }
                }
                
                sectionCard(title: "SoftEther 引擎协议与加速", icon: "cpu.fill") {
                    VStack(spacing: 16) {
                        Toggle(isOn: $engine.settings.useUDPAcceleration) {
                            settingLabel(title: "UDP Acceleration 加速协议", description: "跨洲 VPN 推荐开启：应用层重传优于 TCP 慢启动，高延迟链路显著提速")
                        }
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        #if os(iOS)
                        VStack(alignment: .leading, spacing: 8) {
                            settingLabel(title: "数据流对称加密算法", description: "硬件级 NEON 向量指令集加速")
                            Picker("", selection: $engine.settings.selectedCipher) {
                                Text("AES-256-GCM").tag("AES-256-GCM")
                                Text("AES-128-GCM").tag("AES-128-GCM")
                                Text("ChaCha20-Poly1305").tag("ChaCha20-Poly1305")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        #else
                        HStack {
                            settingLabel(title: "数据流对称加密算法", description: "硬件级 NEON 向量指令集加速")
                            Spacer()
                            Picker("", selection: $engine.settings.selectedCipher) {
                                Text("AES-256-GCM").tag("AES-256-GCM")
                                Text("AES-128-GCM").tag("AES-128-GCM")
                                Text("ChaCha20-Poly1305").tag("ChaCha20-Poly1305")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 160)
                        }
                        #endif
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        #if os(iOS)
                        VStack(alignment: .leading, spacing: 8) {
                            settingLabel(title: "最大 TCP 并发通道数", description: "高延迟链路推荐 4-8 通道突破拥塞窗口，低延迟专线选 1")
                            Picker("", selection: $engine.settings.maxTCPChannels) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                                Text("4").tag(4)
                                Text("8").tag(8)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        #else
                        HStack {
                            settingLabel(title: "最大 TCP 并发通道数", description: "高延迟链路推荐 4-8 通道突破拥塞窗口，低延迟专线选 1")
                            Spacer()
                            Picker("", selection: $engine.settings.maxTCPChannels) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                                Text("4").tag(4)
                                Text("8").tag(8)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 200)
                        }
                        #endif
                    }
                }
                
                sectionCard(title: "核心与系统构建信息", icon: "info.circle.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow(label: "架构支持", value: "ARM64 (Apple Silicon M1/M2/M3/M4 & iOS)")
                        infoRow(label: "编译框架", value: "SwiftUI (macOS 12.0+ / iOS 15.0+)")
                        infoRow(label: "网络驱动模型", value: "macOS Daemon / iOS NetworkExtension")
                        infoRow(label: "SoftEther C Core", value: "v4.44 Build 9807 (arm64)")
                    }
                }

                sectionCard(title: "网络诊断", icon: "stethoscope") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("逐层检测物理链路 / 隧道 / TCP / DNS 的丢包来源")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))

                        Button(action: { engine.runNetworkDiagnostics() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("运行网络诊断")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(accentCyan)
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text("结果输出到日志控制台 (LogConsoleView)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }
            #if os(iOS)
            .padding(16)
            #else
            .padding(24)
            #endif
        }
    }
    
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(accentCyan)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            content()
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
    
    private func settingLabel(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            Text(description).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(accentCyan)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.trailing)
        }
    }
}
