//
//  UpdateDeviceDataOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 13/05/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging
import class WireGuardKitTypes.PublicKey

class UpdateDeviceDataOperation: ResultOperation<StoredDeviceData, TunnelManager.Error> {
    private let interactor: TunnelInteractor
    private let devicesProxy: REST.DevicesProxy

    private var task: Cancellable?

    init(
        dispatchQueue: DispatchQueue,
        interactor: TunnelInteractor,
        devicesProxy: REST.DevicesProxy
    )
    {
        self.interactor = interactor
        self.devicesProxy = devicesProxy

        super.init(dispatchQueue: dispatchQueue)
    }

    override func main() {
        guard case .loggedIn(let accountData, let deviceData) = interactor.deviceState else {
            finish(completion: .failure(.invalidDeviceState))
            return
        }

        task = devicesProxy.getDevice(
            accountNumber: accountData.number,
            identifier: deviceData.identifier,
            retryStrategy: .default,
            completion: { [weak self] completion in
                self?.dispatchQueue.async {
                    self?.didReceiveDeviceResponse(
                        completion: completion
                    )
                }
            })
    }

    override func operationDidCancel() {
        task?.cancel()
        task = nil
    }

    private func didReceiveDeviceResponse(
        completion: OperationCompletion<REST.Device?, REST.Error>
    ) {
        let mappedCompletion = completion
            .mapError { error -> TunnelManager.Error in
                return .restError(error)
            }
            .flatMap { device -> OperationCompletion<REST.Device, TunnelManager.Error> in
                if let device = device {
                    return .success(device)
                } else {
                    return .failure(.deviceRevoked)
                }
            }

        guard let device = mappedCompletion.value else {
            finish(completion: mappedCompletion.assertNoSuccess())
            return
        }

        guard case .loggedIn(let storedAccount, var storedDevice) = interactor.deviceState else {
            finish(completion: .failure(.invalidDeviceState))
            return
        }

        storedDevice.update(from: device)

        let newDeviceState = DeviceState.loggedIn(storedAccount, storedDevice)

        interactor.setDeviceState(newDeviceState, persist: true)

        finish(completion: .success(storedDevice))
    }

}
