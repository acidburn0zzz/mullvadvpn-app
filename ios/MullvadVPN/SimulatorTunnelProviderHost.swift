//
//  SimulatorTunnelProviderHost.swift
//  MullvadVPN
//
//  Created by pronebird on 10/02/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

#if targetEnvironment(simulator)

import Foundation
import enum NetworkExtension.NEProviderStopReason
import Logging

class SimulatorTunnelProviderHost: SimulatorTunnelProviderDelegate {
    private var selectorResult: RelaySelectorResult?

    private let providerLogger = Logger(label: "SimulatorTunnelProviderHost")
    private let dispatchQueue = DispatchQueue(label: "SimulatorTunnelProviderHostQueue")

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        dispatchQueue.async {
            var selectorResult: RelaySelectorResult?

            do {
                let tunnelOptions = PacketTunnelOptions(rawOptions: options ?? [:])

                selectorResult = try tunnelOptions.getSelectorResult()
            } catch {
                self.providerLogger.error(
                    chainedError: AnyChainedError(error),
                    message: """
                             Failed to decode relay selector result passed from the app. \
                             Will continue by picking new relay.
                             """
                )
            }

            self.selectorResult = selectorResult ?? self.pickRelay()

            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        dispatchQueue.async {
            self.selectorResult = nil

            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        dispatchQueue.async {
            let message: TunnelProviderMessage
            do {
                message = try TunnelProviderMessage(messageData: messageData)
            } catch {
                self.providerLogger.error(
                    chainedError: AnyChainedError(error),
                    message: "Failed to decode app message."
                )
                completionHandler?(nil)
                return
            }

            var response: Data?

            switch message {
            case .getTunnelStatus:
                do {
                    var tunnelStatus = PacketTunnelStatus()
                    tunnelStatus.tunnelRelay = self.selectorResult?.packetTunnelRelay

                    response = try TunnelProviderReply(tunnelStatus).encode()
                } catch {
                    self.providerLogger.error(
                        chainedError: AnyChainedError(error),
                        message: "Failed to encode tunnel status reply."
                    )
                }

            case .reconnectTunnel(let aSelectorResult):
                self.reasserting = true
                if let aSelectorResult = aSelectorResult {
                    self.selectorResult = aSelectorResult
                }
                self.reasserting = false
            }

            completionHandler?(response)
        }
    }

    private func pickRelay() -> RelaySelectorResult? {
        guard let cachedRelays = RelayCache.Tracker.shared.getCachedRelays() else {
            providerLogger.error("Failed to obtain relays when picking relay.")
            return nil
        }

        do {
            let tunnelSettings = try SettingsManager.readSettings()

            return try RelaySelector.evaluate(
                relays: cachedRelays.relays,
                constraints: tunnelSettings.relayConstraints
            )
        } catch {
            providerLogger.error(
                chainedError: AnyChainedError(error),
                message: "Failed to pick relay."
            )
            return nil
        }
    }

}

#endif
