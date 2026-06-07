import Foundation
import LocalAuthentication

enum AuthError: Error, LocalizedError {
    case biometricNotAvailable
    case biometricFailed(Error)
    case biometricCancelled

    var errorDescription: String? {
        switch self {
        case .biometricNotAvailable:
            return "Face ID / Touch ID is not available on this device"
        case .biometricFailed(let error):
            return "Biometric authentication failed: \(error.localizedDescription)"
        case .biometricCancelled:
            return "Authentication was cancelled"
        }
    }
}

final class AuthenticationService: Sendable {
    func authenticateWithBiometrics() async throws -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error {
                throw AuthError.biometricFailed(error)
            }
            throw AuthError.biometricNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Cog"
            )
            return success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw AuthError.biometricCancelled
            default:
                throw AuthError.biometricFailed(error)
            }
        }
    }

    var isDeviceAuthAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var isBiometricAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
}
