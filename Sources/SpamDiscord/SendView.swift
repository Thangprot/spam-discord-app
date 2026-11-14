import SwiftUI
import UniformTypeIdentifiers

struct SendView: View {
    @EnvironmentObject var app: AppState
    let channel: Channel
    @State private var showImport = false
    @State private var inputMode = 1 
    
    var body: some View {
        Form {
            Section(header: Text("Kênh đang chọn").font(.caption)) {
                HStack {
                    Image(systemName: channel.type == 5 ? "megaphone" : "number")
                        .foregroundStyle(.blue)
                    Text(channel.displayName).bold()
                }
            }
            
            Section(header: Text("Tốc độ gửi (Delay)").font(.caption)) {
                Slider(value: $app.delaySeconds, in: 0.1...5.0, step: 0.1)
                HStack {
                    Text("Thời gian chờ:")
                    Spacer()
                    Text(String(format: "%.1f giây", app.delaySeconds))
                        .bold()
                        .foregroundStyle(app.delaySeconds < 1.0 ? .red : .blue)
                }
            }
            
            Section(header: Text("Tùy chọn Tag").font(.caption)) {
                Toggle("Tag người dùng", isOn: $app.useTag)
                if app.useTag {
                    TextField("Nhập User ID", text: $app.targetUserId)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Section(header: Text("Nội dung tin nhắn").font(.caption)) {
                Picker("Nguồn dữ liệu", selection: $inputMode) {
                    Text("Nhập trực tiếp").tag(1)
                    Text("File .txt").tag(0)
                }
                .pickerStyle(.segmented)
                .onChange(of: inputMode) { _ in app.parseDirectInput() }
                
                if inputMode == 0 {
                    Button(action: { showImport = true }) {
                        Label("Chọn file từ thiết bị", systemImage: "folder")
                    }
                } else {
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $app.inputText)
                            .frame(minHeight: 120)
                            .padding(4)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                            .onChange(of: app.inputText) { _ in app.parseDirectInput() }
                        
                        if !app.inputText.isEmpty {
                            Button(action: { 
                                app.inputText = "" 
                                app.parseDirectInput()
                                app.hideKeyboard()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                                    .padding(8)
                            }
                        }
                    }
                }
                
                if !app.messages.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Đã nhận diện: \(app.messages.count) tin nhắn")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            }
            
            Section {
                if app.isSending {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.blue)
                            .scaleEffect(1.2)
                        
                        // Hiển thị tổng số tin đã gửi thay vì progress bar
                        Text("Đang gửi liên tục...\nĐã gửi: \(app.totalSent) tin nhắn")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        
                        Button(action: { app.stopSending() }) {
                            Text("DỪNG LẠI").bold().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.vertical, 8)
                } else {
                    Button(action: { app.startSending(channel: channel) }) {
                        Text("BẮT ĐẦU GỬI (LẶP VÔ HẠN)").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(app.messages.isEmpty || (app.useTag && app.targetUserId.isEmpty))
                }
            }
            
            if !app.logs.isEmpty {
                Section(header: Text("Lịch sử hoạt động").font(.caption)) {
                    ForEach(app.logs.reversed()) { log in
                        LogRow(log: log)
                    }
                }
            }
        }
        .navigationTitle("Cấu hình gửi")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { app.hideKeyboard() }
            }
        }
        .fileImporter(
            isPresented: $showImport,
            allowedContentTypes: [UTType.plainText, UTType.text, UTType.item],
            allowsMultipleSelection: false
        ) { res in
            switch res {
            case .success(let urls):
                if let url = urls.first { app.parseFile(url: url) }
            case .failure(let error):
                app.logs.append(LogEntry(text: "Lỗi file: \(error.localizedDescription)", isSuccess: false))
            }
        }
    }
}

struct LogRow: View {
    let log: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: log.isSendingState ? "arrow.triangle.2.circlepath" : (log.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill"))
                .foregroundStyle(log.isSendingState ? .orange : (log.isSuccess ? .green : .red))
                .font(.system(size: 18))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(log.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(log.time, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(log.isSendingState ? Color.orange.opacity(0.1) : (log.isSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1)))
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}