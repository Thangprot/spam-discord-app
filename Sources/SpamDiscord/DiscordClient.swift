import Foundation

class DiscordClient {
    let token: String
    let session: URLSession
    
    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.default
        
        let superProps = """
        {"os":"Mac OS X","browser":"Chrome","device":"","system_locale":"en-US","browser_user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36","browser_version":"126.0.0.0","os_version":"10.15.7","referrer":"","referring_domain":"","referrer_current":"","referring_domain_current":"","release_channel":"stable","client_build_number":305000,"client_event_source":null}
        """
        let superPropsB64 = Data(superProps.utf8).base64EncodedString()
        
        config.httpAdditionalHeaders = [
            "Authorization": token,
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "X-Super-Properties": superPropsB64,
            "X-Discord-Locale": "en-US",
            "Accept": "*/*"
        ]
        self.session = URLSession(configuration: config)
    }
    
    private func checkResponse(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw NSError(domain: "DiscordAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(msg)"])
        }
    }
    
    func validateToken() async throws -> DiscordUser {
        let url = URL(string: "https://discord.com/api/v10/users/@me")!
        let (data, response) = try await session.data(from: url)
        try checkResponse(response, data)
        return try JSONDecoder().decode(DiscordUser.self, from: data)
    }
    
    func getAllGuilds() async throws -> [Guild] {
        let url = URL(string: "https://discord.com/api/v10/users/@me/guilds")!
        let (data, response) = try await session.data(from: url)
        try checkResponse(response, data)
        return try JSONDecoder().decode([Guild].self, from: data)
    }
    
    func getAllChannels(guildId: String) async throws -> [Channel] {
        let url = URL(string: "https://discord.com/api/v10/guilds/\(guildId)/channels")!
        let (data, response) = try await session.data(from: url)
        try checkResponse(response, data)
        return try JSONDecoder().decode([Channel].self, from: data)
    }
    
    func sendMessage(channelId: String, content: String, retries: Int = 3) async throws {
        guard retries > 0 else { throw URLError(.cannotConnectToHost) }
        let url = URL(string: "https://discord.com/api/v10/channels/\(channelId)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["content": content, "tts": false])
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        if http.statusCode == 429 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let retryAfter = json["retry_after"] as? Double {
                try await Task.sleep(nanoseconds: UInt64((retryAfter + 0.5) * 1_000_000_000))
                return try await sendMessage(channelId: channelId, content: content, retries: retries - 1)
            }
        }
        try checkResponse(response, data)
    }
}
