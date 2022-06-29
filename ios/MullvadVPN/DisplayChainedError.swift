//
//  DisplayChainedError.swift
//  MullvadVPN
//
//  Created by pronebird on 04/06/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation
import StoreKit

protocol DisplayChainedError {
    var errorChainDescription: String? { get }
}

extension REST.Error: DisplayChainedError {
    var errorChainDescription: String? {
        switch self {
        case .network(let urlError):
            return String(
                format: NSLocalizedString(
                    "NETWORK_ERROR",
                    tableName: "REST",
                    value: "Network error: %@",
                    comment: ""
                ),
                urlError.localizedDescription
            )
        case .unhandledResponse(let statusCode, let serverResponse):
            return String(
                format: NSLocalizedString(
                    "SERVER_ERROR",
                    tableName: "REST",
                    value: "Unexpected server response: %1$@ (HTTP status: %2$d)",
                    comment: ""
                ),
                serverResponse?.code.rawValue ?? "(no code)",
                statusCode
            )
        case .createURLRequest:
            return NSLocalizedString(
                "SERVER_REQUEST_ENCODING_ERROR",
                tableName: "REST",
                value: "Failure to create URL request",
                comment: ""
            )
        case .decodeResponse:
            return NSLocalizedString(
                "SERVER_SUCCESS_RESPONSE_DECODING_ERROR",
                tableName: "REST",
                value: "Server response decoding error",
                comment: ""
            )
        }
    }
}

extension TunnelManager.Error: DisplayChainedError {
    var errorChainDescription: String? {
        switch self {
        case .unsetTunnel:
            return ""

        case .invalidDeviceState:
            return NSLocalizedString(
                "INVALID_DEVICE_STATE_ERROR",
                tableName: "TunnelManager",
                value: "Cannot complete the request in such device state.",
                comment: ""
            )

        case .deviceRevoked:
            return NSLocalizedString(
                "DEVICE_REVOKED_ERROR",
                tableName: "TunnelManager",
                value: "Device is revoked.",
                comment: ""
            )

        case .relayListUnavailable:
            return NSLocalizedString(
                "RELAYLIST_UNAVAILABLE_ERROR",
                tableName: "TunnelManager",
                value: "Relay list is not available.",
                comment: ""
            )

        case .cannotSatisfyRelayConstraints:
            return NSLocalizedString(
                "CANNOT_SATISFY_RELAY_CONSTRAINTS_ERROR",
                tableName: "TunnelManager",
                value: "Failed to satisfy relay constraints.",
                comment: ""
            )

        case .systemVPNError(let systemError):
            return String(
                format: NSLocalizedString(
                    "SYSTEM_VPN_ERROR",
                    tableName: "TunnelManager",
                    value: "System VPN error: %@",
                    comment: ""
                ),
                systemError.localizedDescription
            )

        case .settingsStoreError(let error):
            return String(
                format: NSLocalizedString(
                    "SETTINGS_STORE_ERROR",
                    tableName: "TunnelManager",
                    value: "Settings store error: %@",
                    comment: ""
                ),
                error.localizedDescription
            )

        case .restError(let restError):
            return String(
                format: NSLocalizedString(
                    "REST_ERROR",
                    tableName: "TunnelManager",
                    value: "REST error: %@",
                    comment: ""
                ),
                restError.localizedDescription
            )

        case .ipcError(let ipcError):
            return String(
                format: NSLocalizedString(
                    "IPC_ERROR",
                    tableName: "TunnelManager",
                    value: "IPC error: %@",
                    comment: ""
                ),
                ipcError.localizedDescription
            )
        }
    }
}

extension SKError: LocalizedError {
    public var errorDescription: String? {
        switch self.code {
        case .unknown:
            return NSLocalizedString(
                "UNKNOWN_ERROR",
                tableName: "StoreKitErrors",
                value: "Unknown error.",
                comment: ""
            )
        case .clientInvalid:
            return NSLocalizedString(
                "CLIENT_INVALID",
                tableName: "StoreKitErrors",
                value: "Client is not allowed to issue the request.",
                comment: ""
            )
        case .paymentCancelled:
            return NSLocalizedString(
                "PAYMENT_CANCELLED",
                tableName: "StoreKitErrors",
                value: "User cancelled the request.",
                comment: ""
            )
        case .paymentInvalid:
            return NSLocalizedString(
                "PAYMENT_INVALID",
                tableName: "StoreKitErrors",
                value: "Invalid purchase identifier.",
                comment: ""
            )
        case .paymentNotAllowed:
            return NSLocalizedString(
                "PAYMENT_NOT_ALLOWED",
                tableName: "StoreKitErrors",
                value: "This device is not allowed to make the payment.",
                comment: ""
            )
        default:
            return self.localizedDescription
        }
    }
}

extension AppStorePaymentManager.Error: DisplayChainedError {
    var errorChainDescription: String? {
        switch self {
        case .noAccountSet:
            return NSLocalizedString(
                "NO_ACCOUNT_SET_ERROR",
                tableName: "AppStorePaymentManager",
                value: "Internal error: account is not set.",
                comment: ""
            )

        case .validateAccount(let restError):
            let reason = restError.errorChainDescription ?? ""

            if case .unhandledResponse(_, let serverErrorResponse) = restError,
               serverErrorResponse?.code == .invalidAccount
            {
                return String(
                    format: NSLocalizedString(
                        "INVALID_ACCOUNT_ERROR",
                        tableName: "AppStorePaymentManager",
                        value: "Cannot add credit to invalid account.",
                        comment: ""
                    ), reason
                )
            } else {
                let reason = restError.errorChainDescription ?? ""

                return String(
                    format: NSLocalizedString(
                        "VALIDATE_ACCOUNT_ERROR",
                        tableName: "AppStorePaymentManager",
                        value: "Failed to validate account token: %@",
                        comment: ""
                    ), reason
                )
            }

        case .readReceipt(let readReceiptError):
            switch readReceiptError {
            case .refresh(let storeError):
                let skErrorMessage = (storeError as? SKError)?.errorDescription ?? storeError.localizedDescription

                return String(
                    format: NSLocalizedString(
                        "REFRESH_RECEIPT_ERROR",
                        tableName: "AppStorePaymentManager",
                        value: "Cannot refresh the AppStore receipt: %@",
                        comment: ""
                    ),
                    skErrorMessage
                )
            case .io(let ioError):
                return String(
                    format: NSLocalizedString(
                        "READ_RECEIPT_ERROR",
                        tableName: "AppStorePaymentManager",
                        value: "Cannot read the AppStore receipt from disk: %@",
                        comment: ""
                    ),
                    ioError.localizedDescription
                )
            case .doesNotExist:
                return NSLocalizedString(
                    "RECEIPT_NOT_FOUND_ERROR",
                    tableName: "AppStorePaymentManager",
                    value: "AppStore receipt is not found on disk.",
                    comment: ""
                )
            }

        case .sendReceipt(let restError):
            let reason = restError.errorChainDescription ?? ""
            let errorFormat = NSLocalizedString(
                "SEND_RECEIPT_ERROR",
                tableName: "AppStorePaymentManager",
                value: "Failed to send the receipt to server: %@",
                comment: ""
            )
            let recoverySuggestion = NSLocalizedString(
                "SEND_RECEIPT_RECOVERY_SUGGESTION",
                tableName: "AppStorePaymentManager",
                value: "Please retry by using the \"Restore purchases\" button.",
                comment: ""
            )
            var errorString = String(format: errorFormat, reason)
            errorString.append("\n\n")
            errorString.append(recoverySuggestion)
            return errorString

        case .storePayment(let storeError):
            return (storeError as? SKError)?.errorDescription ?? storeError.localizedDescription
        }
    }
}
