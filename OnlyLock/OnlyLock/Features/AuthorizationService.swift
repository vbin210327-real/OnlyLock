import Combine
import FamilyControls
import Foundation

@MainActor
final class AuthorizationService: ObservableObject {
    @Published private(set) var status: AuthorizationStatus

    private let center: AuthorizationCenter
    private var cancellable: AnyCancellable?

    init(center: AuthorizationCenter = .shared) {
        self.center = center
        status = center.authorizationStatus

        cancellable = center.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] newStatus in
                self?.status = newStatus
            }
    }

    var isApproved: Bool {
        status == .approved
    }

    func refreshStatus() {
        status = center.authorizationStatus
    }

    func requestAuthorization() async throws {
        try await center.requestAuthorization(for: .individual)
        status = center.authorizationStatus
    }

    func revokeAuthorization() async throws {
        try await withCheckedThrowingContinuation { continuation in
            center.revokeAuthorization { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        status = center.authorizationStatus
    }
}
