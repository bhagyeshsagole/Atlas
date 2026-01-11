import Foundation
import Supabase

/// Centralized Supabase client so auth and feature calls share the same session.
enum SupabaseService {
    static let shared: SupabaseClient? = {
        SupabaseClientProvider.makeClient()
    }()
}
