import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
    @EnvironmentObject var app: AppState
    let channel: Channel
    @State private var showImport = false
    
    // Trạng thái chọn nhập liệu: 0 là File, 1 là Trực tiếp
    @State private var inputMode = 1 
    
    var body: some View {
        Form {
            Section("Kênh") { Text(channel.displayName).bold() }
            
            Section("Tốc độ gửi (Delay)") {
                Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1)
                Text(String(format: "%.1f giây", app.delaySeconds)).foregroundStyle(app.delaySeconds < 1.0 ? Color.red : Color.primary)
            }
            
            Section("Tùy chọn Tag") {
                Toggle("Tag người dùng vào cuối tin nhắn", isOn: $app.useTag)
                if app.useTag {
                    TextField("Nhập User ID (dãy số)", text: $app.targetUserId)
                        .keyboardType(.numberPad)
                }
            }
            
            Section("Nội dung tin nhắn") {
                Picker("Nguồn dữ liệu", selection: $inputMode) {
                    Text("Nhập trực tiếp").tag(1)
                    Text("Chọn từ File").tag(0)
                }
                .pickerStyle(.segmented)
                .onChange(of: inputMode) { _ in
                    app.parseDirectInput() // Cập nhật lại danh sách khi đổi chế độ
                }
                
                if inputMode == 0 {
                    Button("Chọn file .txt") { showImport = true }
                } else {
                    TextEditor(text: $app.inputText)
                        .frame(minHeight: 100)
                        .onChange(of: app.inputText) { _ in
                            app.parseDirectInput()
                        }
                }
                
                if !app.messages.isEmpty {
                    Text("Đã nhận diện: \(app.messages.count) tin nhắn").foregroundStyle(Color.green).font(.caption)
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
                    .disabled(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty))
                }
            }
            
            if !app.logs.isEmpty {
                Section("Logs") {
                    ForEach(app.logs.suffix(20)) { log in
                        Text(log.text).font(.caption).foregroundStyle(log.isSuccess ? Color.primary : Color.red)
                    }
                }
            }
        }
        .navigationTitle("Cấu hình")
        .fileImporter(
            isPresented: $showImport,
            allowedContentTypes: [UTType.plainText, UTType.text, UTType.item], // Mở rộng loại file để dễ chọn
            allowsMultipleSelection: false
        ) { res in
            switch res {
            case .success(let urls):
                if let url = urls.first { app.parseFile(url: url) }
            case .failure(let error):
                app.logs.append(LogEntry(text: "Lỗi đọc file: \(error.localizedDescription)", isSuccess: false))
            }
        }
    }
}