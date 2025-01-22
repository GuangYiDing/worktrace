//
//  ContentView.swift
//  work-trace
//
//  Created by GuangYi Ding on 2025/1/13.
//

import SwiftUI
import SwiftData
import Photos
import AVFoundation
import Inject



struct ContentView: View {
    @State private var selectedTab = 0 {
        didSet {
            AppState.shared.selectedTab = selectedTab
        }
    }
    @State private var showingCamera = false
    @State private var showingAudioRecorder = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var permissionAlertTitle = ""
    @State private var isPreparingCamera = false
    @EnvironmentObject private var settings: Settings
    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func showCamera() {
        isPreparingCamera = true
        showingCamera = true
    }
    
    private func showAudioRecorder() {
        showingAudioRecorder = true
    }
    
    private func requestFileAccess() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            // Try to create a test file to verify write access
            let testFile = documentsPath.appendingPathComponent("test.txt")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
        } catch {
            DispatchQueue.main.async {
                permissionAlertTitle = "存储权限"
                permissionAlertMessage = "请在设置中开启文件存储权限，以便保存工作记录"
                showingPermissionAlert = true
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            PhotoListView()
                .tabItem {
                    Label("工作记录", systemImage: "photo.stack")
                        .font(.system(size: 24))
                }
                .tag(0)
            
            // 拍照按钮作为中间的 tab item
            Color.clear  // 空白页面
                .tabItem {
                    Label("拍照", systemImage: "camera.fill")
                        .font(.system(size: 24))
                }
                .tag(1)

            Color.clear  // 空白页面
                .tabItem {
                    Label("录音", systemImage: "mic.fill")
                        .font(.system(size: 24))
                }
                .tag(2)
            
            SettingsView() 
                .tabItem {
                    Label("设置", systemImage: "gear")
                        .font(.system(size: 24))
                }
                .tag(3)
        }
        .navigationTitle("工作留痕")
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 1 {
                selectedTab = oldValue
                showCamera()
            } else if newValue == 2 {
                selectedTab = oldValue
                showAudioRecorder()
            }
        }
        .sheet(isPresented: $showingCamera, onDismiss: {
            // 相机关闭后切换到工作记录标签页
            selectedTab = 0
            // 重置全局状态
            AppState.shared.shouldShowCamera = false
        }) {
            ZStack {
                CameraView()
                    .environmentObject(settings)
                    .onAppear {
                        // 给相机一点时间初始化
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isPreparingCamera = false
                        }
                    }
                if isPreparingCamera {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        )
                }
            }
        }
        .sheet(isPresented: $showingAudioRecorder) {
            AudioRecorderView()
                .environmentObject(settings)
        }
        .onAppear {
            // Request notification permission
            NotificationManager.shared.requestPermission { granted in
                if !granted {
                    permissionAlertTitle = "通知权限"
                    permissionAlertMessage = "请在设置中开启通知权限，以便接收工作打卡提醒"
                    showingPermissionAlert = true
                }
            }
            // 同步初始标签状态
            selectedTab = AppState.shared.selectedTab
        }
        .onChange(of: AppState.shared.selectedTab) { _, newValue in
            selectedTab = newValue
        }
        .onChange(of: AppState.shared.shouldShowCamera) { _, newValue in
            if newValue {
                showCamera()
            }
        }
        .onChange(of: AppState.shared.shouldShowAudioRecorder) { _, newValue in
            if newValue {
                showAudioRecorder()
                // Reset the global state
                AppState.shared.shouldShowAudioRecorder = false
            }
        }
        .alert(permissionAlertTitle, isPresented: $showingPermissionAlert) {
            Button("确定") {
                showingPermissionAlert = false
            }
        } message: {
            Text(permissionAlertMessage)
        }
        .enableInjection()
    }
}
                                                                                                                                                                                                                                                                                                                                                                                                                                
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Company.self, configurations: config)
    
    return ContentView()
        .modelContainer(container)
}

