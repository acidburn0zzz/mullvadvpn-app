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

    private var tunnelStatus = PacketTunnelStatus()
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
                    message: "Failed to decode relay selector result passed from the app. Will continue by picking new relay."
                )
            }

            if selectorResult == nil {
                selectorResult = self.pickRelay()
            }

            self.tunnelStatus.tunnelRelay = selectorResult?.packetTunnelRelay

            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        dispatchQueue.async {
            self.tunnelStatus = PacketTunnelStatus(isNetworkReachable: true, connectingDate: nil, tunnelRelay: nil)

            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        dispatchQueue.async {
            let request: TunnelIPC.Request
            do {
                request = try TunnelIPC.Coding.decodeRequest(messageData)
            } catch {
                self.providerLogger.error(chainedError: AnyChainedError(error), message: "Failed to decode the IPC request.")
                completionHandler?(nil)
                return
            }

            var response: Data?

            switch request {
            case .getTunnelStatus:
                do {
                    response = try TunnelIPC.Coding.encodeResponse(self.tunnelStatus)
                } catch {
                    self.providerLogger.error(chainedError: AnyChainedError(error), message: "Failed to encode tunnel status IPC response.")
                }

            case .reconnectTunnel(let inputSelectorResult):
                self.reasserting = true
                let selectorResult = inputSelectorResult ?? self.pickRelay()
                self.tunnelStatus.tunnelRelay = selectorResult?.packetTunnelRelay
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
