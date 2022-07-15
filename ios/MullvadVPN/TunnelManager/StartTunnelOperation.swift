//
//  StartTunnelOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 15/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import NetworkExtension

class StartTunnelOperation: ResultOperation<(), TunnelManager.Error> {
    typealias EncodeErrorHandler = (Error) -> Void

    private let interactor: TunnelInteractor
    private var encodeErrorHandler: EncodeErrorHandler?

    init(
        dispatchQueue: DispatchQueue,
        interactor: TunnelInteractor,
        encodeErrorHandler: @escaping EncodeErrorHandler,
        completionHandler: @escaping CompletionHandler
    )
    {
        self.interactor = interactor
        self.encodeErrorHandler = encodeErrorHandler

        super.init(
            dispatchQueue: dispatchQueue,
            completionQueue: dispatchQueue,
            completionHandler: completionHandler
        )
    }

    override func main() {
        guard case .loggedIn = interactor.deviceState else {
            finish(completion: .failure(.invalidDeviceState))
            return
        }

        switch interactor.tunnelStatus.state {
        case .disconnecting(.nothing):
            interactor.updateTunnelState(.disconnecting(.reconnect))

            finish(completion: .success(()))

        case .disconnected, .pendingReconnect:
            guard let cachedRelays = RelayCache.Tracker.shared.getCachedRelays() else {
                finish(completion: .failure(.relayListUnavailable))
                return
            }

            createAndStartTunnel(
                relayConstraints: interactor.settings.relayConstraints,
                cachedRelays: cachedRelays
            )

        default:
            // Do not attempt to start the tunnel in all other cases.
            finish(completion: .success(()))
        }
    }

    private func createAndStartTunnel(relayConstraints: RelayConstraints, cachedRelays: RelayCache.CachedRelays) {
        let selectorResult = RelaySelector.evaluate(
            relays: cachedRelays.relays,
            constraints: relayConstraints
        )

        guard let selectorResult = selectorResult else {
            finish(completion: .failure(.cannotSatisfyRelayConstraints))
            return
        }

        Self.makeTunnelProvider { makeTunnelProviderResult in
            self.dispatchQueue.async {
                switch makeTunnelProviderResult {
                case .success(let tunnelProvider):
                    let startTunnelResult = Result {
                        try self.startTunnel(
                            tunnelProvider: tunnelProvider,
                            selectorResult: selectorResult
                        )

                    }.mapError { error -> TunnelManager.Error in
                        return .systemVPNError(error)
                    }

                    self.finish(completion: OperationCompletion(result: startTunnelResult))

                case .failure(let error):
                    self.finish(completion: .failure(error))
                }
            }
        }
    }

    private func startTunnel(tunnelProvider: TunnelProviderManagerType, selectorResult: RelaySelectorResult) throws {
        var tunnelOptions = PacketTunnelOptions()

        do {
            try tunnelOptions.setSelectorResult(selectorResult)
        } catch {
            encodeErrorHandler?(error)
        }

        encodeErrorHandler = nil

        interactor.setTunnel(Tunnel(tunnelProvider: tunnelProvider), shouldRefreshTunnelState: false)
        interactor.resetTunnelState(to: .connecting(selectorResult.packetTunnelRelay))

        try tunnelProvider.connection.startVPNTunnel(options: tunnelOptions.rawOptions())
    }

    private class func makeTunnelProvider(completionHandler: @escaping (Result<TunnelProviderManagerType, TunnelManager.Error>) -> Void) {
        TunnelProviderManagerType.loadAllFromPreferences { tunnelProviders, error in
            if let error = error {
                completionHandler(.failure(.systemVPNError(error)))
                return
            }

            let protocolConfig = NETunnelProviderProtocol()
            protocolConfig.providerBundleIdentifier = ApplicationConfiguration.packetTunnelExtensionIdentifier
            protocolConfig.serverAddress = ""

            let tunnelProvider = tunnelProviders?.first ?? TunnelProviderManagerType()
            tunnelProvider.isEnabled = true
            tunnelProvider.localizedDescription = "WireGuard"
            tunnelProvider.protocolConfiguration = protocolConfig

            // Enable on-demand VPN, always connect the tunnel when on Wi-Fi or cellular.
            let alwaysOnRule = NEOnDemandRuleConnect()
            alwaysOnRule.interfaceTypeMatch = .any
            tunnelProvider.onDemandRules = [alwaysOnRule]
            tunnelProvider.isOnDemandEnabled = true

            tunnelProvider.saveToPreferences { error in
                if let error = error {
                    completionHandler(.failure(.systemVPNError(error)))
                    return
                }

                // Refresh connection status after saving the tunnel preferences.
                // Basically it's only necessary to do for new instances of
                // `NETunnelProviderManager`, but we do that for the existing ones too
                // for simplicity as it has no side effects.
                tunnelProvider.loadFromPreferences { error in
                    if let error = error {
                        completionHandler(.failure(.systemVPNError(error)))
                    } else {
                        completionHandler(.success(tunnelProvider))
                    }
                }
            }
        }
    }
}
