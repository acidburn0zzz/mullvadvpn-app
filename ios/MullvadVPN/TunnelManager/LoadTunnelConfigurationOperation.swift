//
//  LoadTunnelConfigurationOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 16/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging

class LoadTunnelConfigurationOperation: ResultOperation<(), TunnelManager.Error> {
    private let logger = Logger(label: "LoadTunnelConfigurationOperation")
    private let interactor: TunnelInteractor

    init(dispatchQueue: DispatchQueue, interactor: TunnelInteractor) {
        self.interactor = interactor

        super.init(dispatchQueue: dispatchQueue)
    }

    override func main() {
        TunnelProviderManagerType.loadAllFromPreferences { tunnels, error in
            self.dispatchQueue.async {
                if let error = error {
                    self.finish(completion: .failure(.systemVPNError(error)))
                } else {
                    self.didLoadVPNConfigurations(tunnels: tunnels)
                }
            }
        }
    }

    private func didLoadVPNConfigurations(tunnels: [TunnelProviderManagerType]?) {
        let settingsResult = readSettings()
        let deviceStateResult = readDeviceState()

        let tunnel = tunnels?.first.map { tunnelProvider in
            return Tunnel(tunnelProvider: tunnelProvider)
        }

        let settings = settingsResult.flattenValue()
        let deviceState = deviceStateResult.flattenValue()

        interactor.setSettings(settings ?? TunnelSettingsV2(), persist: false)
        interactor.setDeviceState(deviceState ?? .loggedOut, persist: false)

        if let tunnel = tunnel, deviceState == nil {
            logger.debug("Remove orphaned VPN configuration.")

            tunnel.removeFromPreferences { error in
                if let error = error {
                    self.logger.error(
                        chainedError: AnyChainedError(error),
                        message: "Failed to remove VPN configuration."
                    )
                }
                self.finishOperation(tunnel: nil)
            }
        } else {
            finishOperation(tunnel: tunnel)
        }
    }
    private func finishOperation(tunnel: Tunnel?) {
        interactor.setTunnel(tunnel, shouldRefreshTunnelState: true)
        interactor.setLoadedConfiguration()

        finish(completion: .success(()))
    }

    private func readSettings() -> Result<TunnelSettingsV2?, TunnelManager.Error> {
        return Result { try SettingsManager.readSettings() }
            .flatMapError { error in
                if let error = error as? KeychainError, error == .itemNotFound {
                    logger.debug("Settings not found in keychain.")

                    return .success(nil)
                } else if let error = error as? DecodingError {
                    logger.error(
                        chainedError: AnyChainedError(error),
                        message: "Cannot decode settings. Will attempt to delete them from keychain."
                    )

                    return Result { try SettingsManager.deleteSettings() }
                        .mapError { error in
                            logger.error(
                                chainedError: AnyChainedError(error),
                                message: "Failed to delete settings from keychain."
                            )

                            return .settingsStoreError(error)
                        }
                        .map { _ in
                            return nil
                        }
                } else {
                    return .failure(.settingsStoreError(error))
                }
            }
    }

    private func readDeviceState() -> Result<DeviceState?, TunnelManager.Error> {
        return Result { try SettingsManager.readDeviceState() }
            .flatMapError { error in
                if let error = error as? KeychainError, error == .itemNotFound {
                    logger.debug("Device state not found in keychain.")

                    return .success(nil)
                } else if let error = error as? DecodingError {
                    logger.error(
                        chainedError: AnyChainedError(error),
                        message: "Cannot decode device state. Will attempt to delete it from keychain."
                    )

                    return Result { try SettingsManager.deleteDeviceState() }
                        .mapError { error in
                            logger.error(
                                chainedError: AnyChainedError(error),
                                message: "Failed to delete device state from keychain."
                            )

                            return .settingsStoreError(error)
                        }
                        .map { _ in
                            return nil
                        }
                } else {
                    return .failure(.settingsStoreError(error))
                }
            }
    }
}
