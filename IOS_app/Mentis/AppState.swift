import SwiftUI

final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userEmail: String = ""

    init() {
        if let uid = APIClient.shared.userId {
            isLoggedIn = uid > 0
            userEmail = UserDefaults.standard.string(forKey: "userEmail") ?? ""
        }
    }

    func login(userId: Int, email: String) {
        APIClient.shared.userId = userId
        UserDefaults.standard.set(email, forKey: "userEmail")
        userEmail = email
        isLoggedIn = true
    }

    func logout() {
        APIClient.shared.userId = nil
        UserDefaults.standard.removeObject(forKey: "userEmail")
        userEmail = ""
        isLoggedIn = false
    }
}
