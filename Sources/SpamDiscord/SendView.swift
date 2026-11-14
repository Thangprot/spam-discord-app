import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
    @EnvironmentObject var app: AppState
    let channel: Channel
    @State private var showImporter = false
    
    var body: some View {
        Form {
            Section("Kênh đã chọn") {
                Text(channel.displayName).bold()
            }
            
            Section("Tốc độ gửi (Delay)") {
                Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1)
                Text("Delay: \(String(format: "%.1f", app.delaySeconds)) giây")
                    .foregroundStyle(app.delaySeconds < 1.0 ? .red : .primary)
            }
            
            Section("Tag người dùng") {
                TextField("Nhập User ID (dãy số)", text: $app.targetUserId)
                    .keyboardType(.numberPad)
            }
            
            Section("Nội dung File TXT") {
                Button("Chọn file (.txt)") { showImporter = true }
                if !app.messages.isEmpty {
                    Text("Đã nạp \(app.messages.count) dòng hợp lệ.").foregroundStyle(.green)
                }
            }
            
            Section {
                if app.isSending {
                    ProgressView(value: Double(app.currentIndex), total: Double(app.messages.count))
                    Button("Dừng lại", role: .destructive) { app.stopSending() }
                } else {
                    Button("BẮT ĐẦU SPAM") {
                        app.startSending(channel: channel)
                    }
                    .disabled(app.messages.isEmpty || app.targetUserId.isEmpty || !app.targetUserId.allSatisfy(\.isNumber))
                }
            }
            
            if !app.logs.isEmpty {
                Section("Logs") {
                    ForEach(app.logs.suffix(20)) { log in
                        Text(log.text)
                            .font(.caption)
                            .foregroundStyle(log.isSuccess ? .primary : .red)
                    }
                }
            }
        }
        .navigationTitle("Cấu hình gửi")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText]) { result in
            if case .success(let url) = result { app.parseFile(url: url) }
        }
    }
}