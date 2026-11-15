// MainView.swift
// Modern Dark-themed Premium UI for SoftEther VPN Client
// Displays Real SoftEther Client Connection Status & Assigned IP

import SwiftUI

public struct MainView: View {
    @EnvironmentObject var engine: SoftEtherEngine
    @State private var selectedTab: Int = 0
    @State private var pulseAnimation: Bool = false
    
    // Theme Colors
    private let bgGradient = LinearGradient(
        gradient: Gradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]),
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    
    private let accentCyan = Color(red: 0.0, green: 0.83, blue: 1.0)
    private let accentEmerald = Color(red: 0.0, green: 0.9, blue: 0.55)
    
    public init() {}
    
    public var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()
            
            #if os(macOS)
            HStack(spacing: 0) {
                sidebarView
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                tabContent
            }
            #else
            VStack(spacing: 0) {
                tabContent
                
                bottomTabBar
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Sidebar (macOS)
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accentCyan, accentEmerald], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .shadow(color: accentCyan.opacity(0.5), radius: 8)
                    
                    Image(systemName: "shield.checkerboard")
                        .foregroundColor(.black)
                        .font(.system(size: 20, weight: .bold))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("SoftEther Client")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Native ARM64 Driver")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accentCyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Nav Items
            VStack(spacing: 8) {
                navButton(title: "VPN 连接状态", icon: "bolt.shield.fill", index: 0)
                navButton(title: "服务器节点管理", icon: "server.rack", index: 1)
                navButton(title: "控制台与日志", icon: "terminal.fill", index: 2)
                navButton(title: "高级首选项", icon: "gearshape.fill", index: 3)
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            // Engine Info Badge
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(engine.state == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(engine.state.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                Text("Core: SoftEther v4.44 (Native ARM64)")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            .padding(12)
        }
        .frame(width: 220)
        .background(Color.black.opacity(0.2))
    }
    
    private func navButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(selectedTab == index ? accentCyan : .white.opacity(0.5))
                
                Text(title)
                    .font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                    .foregroundColor(selectedTab == index ? .white : .white.opacity(0.6))
                
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                selectedTab == index ?
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)) :
                RoundedRectangle(cornerRadius: 10).fill(Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Tab Content Switcher
    private var tabContent: some View {
        ZStack {
            switch selectedTab {
            case 0: vpnDashboardView
            case 1: ServerConfigView()
            case 2: LogConsoleView()
            case 3: SettingsView()
            default: vpnDashboardView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Dashboard (Tab 0)
    private var vpnDashboardView: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header Status Text
                VStack(spacing: 6) {
                    Text(engine.state == .connected ? "加密隧道已开启 • 服务端已上线" : (engine.state == .connecting ? "正在建立加密隧道..." : "防护未开启"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    if let current = engine.currentConfig {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(accentCyan)
                            Text("目标节点: \(current.name) (\(current.host):\(current.port))")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                
                // Big Connect Button with Animated Pulsing Glow
                ZStack {
                    Circle()
                        .fill(engine.state == .connected ? accentEmerald.opacity(0.15) : accentCyan.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulseAnimation ? 1.15 : 0.95)
                        .animation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulseAnimation)
                        .onAppear { pulseAnimation = true }
                    
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: engine.state == .connected ? [accentEmerald, Color.blue] : [accentCyan, Color.purple],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 155, height: 155)
                        .shadow(color: engine.state == .connected ? accentEmerald.opacity(0.6) : accentCyan.opacity(0.5), radius: 12)
                    
                    Button(action: {
                        withAnimation(.spring()) {
                            engine.toggleConnect()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: engine.state == .connected ?
                                        [Color(red: 0.05, green: 0.25, blue: 0.18), Color(red: 0.02, green: 0.15, blue: 0.1)] :
                                        [Color(red: 0.12, green: 0.15, blue: 0.25), Color(red: 0.06, green: 0.08, blue: 0.15)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(width: 135, height: 135)
                            
                            VStack(spacing: 6) {
                                Image(systemName: "power")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundColor(engine.state == .connected ? accentEmerald : accentCyan)
                                
                                Text(engine.state == .connected ? "断开" : (engine.state == .connecting ? "取消" : "一键连接"))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Assigned IP Address Card
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .foregroundColor(accentCyan)
                        Text("客户端 IP:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(engine.assignedIP)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(engine.state == .connected ? accentEmerald : .white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    
                    Divider().frame(height: 16).background(Color.white.opacity(0.1))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundColor(accentEmerald)
                        Text("保护时长:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(engine.formattedDuration)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(20)
                .padding(.horizontal, 12)
                
                // Real-time Traffic Cards
                HStack(spacing: 12) {
                    trafficCard(
                        title: "实时下载速率",
                        value: String(format: "%.1f KB/s", engine.traffic.downloadSpeedKbps),
                        total: String(format: "%.2f MB", engine.traffic.totalRecvMB),
                        icon: "arrow.down.circle.fill",
                        color: accentCyan
                    )
                    
                    trafficCard(
                        title: "实时上传速率",
                        value: String(format: "%.1f KB/s", engine.traffic.uploadSpeedKbps),
                        total: String(format: "%.2f MB", engine.traffic.totalSentMB),
                        icon: "arrow.up.circle.fill",
                        color: accentEmerald
                    )
                }
                #if os(iOS)
                .padding(.horizontal, 16)
                #else
                .padding(.horizontal, 24)
                #endif
                .padding(.bottom, 24)
            }
        }
    }
    
    private func trafficCard(title: String, value: String, total: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            HStack {
                Text("累计流量:")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Text(total)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    #if os(iOS)
    private var bottomTabBar: some View {
        HStack {
            bottomTabButton(title: "状态", icon: "bolt.shield.fill", index: 0)
            Spacer()
            bottomTabButton(title: "节点", icon: "server.rack", index: 1)
            Spacer()
            bottomTabButton(title: "日志", icon: "terminal.fill", index: 2)
            Spacer()
            bottomTabButton(title: "设置", icon: "gearshape.fill", index: 3)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.4))
    }
    
    private func bottomTabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(selectedTab == index ? accentCyan : .white.opacity(0.4))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(selectedTab == index ? .white : .white.opacity(0.4))
            }
        }
    }
    #endif
}
