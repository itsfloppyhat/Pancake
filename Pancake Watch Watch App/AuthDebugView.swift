import SwiftUI

struct AuthDebugView: View {
    @ObservedObject var auth: AuthManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Auth Status
                VStack(spacing: 8) {
                    Text("Auth Status")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: auth.isSignedIn ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(auth.isSignedIn ? .green : .red)
                        Text(auth.isSignedIn ? "Signed In" : "Not Signed In")
                            .font(.subheadline)
                    }
                    
                    if let userID = auth.userID {
                        Text("User ID: \(userID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                // Debug Actions
                VStack(spacing: 8) {
                    Text("Debug Actions")
                        .font(.headline)
                    
                    Button("Force Sign In") {
                        print("🔐 Debug: Force sign in tapped")
                        auth.signIn()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Sign Out") {
                        print("🔐 Debug: Sign out tapped")
                        auth.signOut()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Clear UserDefaults") {
                        print("🔐 Debug: Clearing UserDefaults")
                        UserDefaults.standard.removeObject(forKey: "appleSignInUserID")
                        UserDefaults.standard.removeObject(forKey: "appleSignInUserIDValue")
                        // Force refresh by signing out and back in
                        auth.signOut()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                // Error Display
                if let error = auth.lastError {
                    VStack(spacing: 8) {
                        Text("Last Error")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .navigationTitle("Auth Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    AuthDebugView(auth: AuthManager.shared)
}
