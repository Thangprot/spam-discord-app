import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
    @EnvironmentObject var app: AppState
    let channel: Channel
    @State private var showImport = false
    
    var body: some View {
        Form {
            Section("Kênh") { Text(channel.displayName).bold() }
            
            Section("Delay (giây)") {
                Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1)
                // Đã sửa: Thêm Color.
                Text(String(format: "%.1f giây", app.delaySeconds)).foregroundStyle(app.delaySeconds < 1.0 ? Color.red : Color.primary)
            }
            
            Section("Tag User ID") {
                TextField("Nhập dãy số ID", text: $app.targetUserId).keyboardType(.numberPad)
            }
            
            Section("Nội dung") {
                Button("Chọn file .txt") { showImport = true }
                if !app.messages.isEmpty { Text("Đã nạp \(app.messages.count) dòng").foregroundStyle(Color.green) }
            }
            
            Section {
                if app.isSending {
                    ProgressView(value: Double(app.currentIndex), total: Double(app.messages.count))
                    Button("Dừng", role: .destructive) { app.stopSending() }
                } else {
                    Button("BẮT ĐẦU SPAM") { app.startSending(channel: channel) }
                        .disabled(app.messages.isEmpty || app.targetUserId.isEmpty || !app.targetUserId.allSatisfy(\.isNumber))
                }
            }
            
            if !app.logs.isEmpty {
                Section("Logs") {
                    ForEach(app.logs.suffix(20)) { log in
                        // Đã sửa: Thêm Color.
                        Text(log.text).font(.caption).foregroundStyle(log.isSuccess ? Color.primary : Color.red)
                    }
                }
            }
        }
        .navigationTitle("Cấu hình")
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.plainText]) { res in
            if case .success(let url) = res { app.parseFile(url: url) }
        }
    }
}