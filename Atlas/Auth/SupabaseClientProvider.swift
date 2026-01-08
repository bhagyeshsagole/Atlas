import Foundation
import Supabase

enum SupabaseClientProvider {
    private static var cachedClient: SupabaseClient?
    private static var didWarnMissingConfig = false

    static func makeClient() -> SupabaseClient? {
        if let cachedClient {
            return cachedClient
        }

        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty
        else {
            if !didWarnMissingConfig {
                #if DEBUG
                print("[AUTH][WARN] Supabase configuration missing. Set SUPABASE_URL and SUPABASE_ANON_KEY in Info.plist.")
                #endif
                didWarnMissingConfig = true
            }
            return nil
        }

        let authOptions = SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
        let options = SupabaseClientOptions(auth: authOptions)
        let client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey, options: options)
        cachedClient = client
        return client
    }
}
