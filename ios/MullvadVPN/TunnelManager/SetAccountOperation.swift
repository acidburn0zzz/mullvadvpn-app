//
//  SetAccountOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 16/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import class WireGuardKitTypes.PublicKey
import class WireGuardKitTypes.PrivateKey
import Logging

enum SetAccountAction {
    /// Set new account.
    case new

    /// Set existing account.
    case existing(String)

    /// Unset account.
    case unset

    var taskName: String {
        switch self {
        case .new:
            return "Set new account"
        case .existing:
            return "Set existing account"
        case .unset:
            return "Unset account"
        }
    }
}

private struct SetAccountResult {
    let accountData: StoredAccountData
    let privateKey: PrivateKey
    let device: REST.Device
}

private struct SetAccountContext: OperationInputContext {
    var accountData: StoredAccountData?
    var privateKey: PrivateKey?
    var device: REST.Device?

    func reduce() -> SetAccountResult? {
        guard let accountData = accountData,
              let privateKey = privateKey,
              let device = device else {
                  return nil
              }

        return SetAccountResult(
            accountData: accountData,
            privateKey: privateKey,
            device: device
        )
    }
}

class SetAccountOperation: ResultOperation<StoredAccountData?, TunnelManager.Error> {
    private let interactor: TunnelInteractor
    private let accountsProxy: REST.AccountsProxy
    private let devicesProxy: REST.DevicesProxy
    private let action: SetAccountAction

    private let logger = Logger(label: "SetAccountOperation")
    private let operationQueue = AsyncOperationQueue()

    private var children: [Operation] = []

    init(
        dispatchQueue: DispatchQueue,
        interactor: TunnelInteractor,
        accountsProxy: REST.AccountsProxy,
        devicesProxy: REST.DevicesProxy,
        action: SetAccountAction
    )
    {
        self.interactor = interactor
        self.accountsProxy = accountsProxy
        self.devicesProxy = devicesProxy
        self.action = action

        super.init(dispatchQueue: dispatchQueue)
    }

    override func main() {
        var deleteDeviceOperation: AsyncOperation?
        if case .loggedIn(let accountData, let deviceData) = interactor.deviceState {
            let operation = getDeleteDeviceOperation(
                accounNumber: accountData.number,
                deviceIdentifier: deviceData.identifier
            )
            deleteDeviceOperation = operation
        }

        let deleteSettingsOperation = getDeleteSettingsOperation()
        deleteSettingsOperation.addCondition(
            NoFailedDependenciesCondition(ignoreCancellations: false)
        )

        if let deleteDeviceOperation = deleteDeviceOperation {
            deleteSettingsOperation.addDependency(deleteDeviceOperation)
        }

        let setupAccountOperations = getAccountDataOperation()
            .flatMap { accountOperation -> [Operation] in
                accountOperation.addCondition(
                    NoFailedDependenciesCondition(ignoreCancellations: false)
                )
                accountOperation.addDependency(deleteSettingsOperation)

                let createDeviceOperation = getCreateDeviceOperation()
                createDeviceOperation.addCondition(
                    NoFailedDependenciesCondition(ignoreCancellations: false)
                )
                createDeviceOperation.inject(from: accountOperation)

                let saveSettingsOperation = getSaveSettingsOperation()
                saveSettingsOperation.addCondition(
                    NoFailedDependenciesCondition(ignoreCancellations: false)
                )

                saveSettingsOperation.injectMany(context: SetAccountContext())
                    .inject(from: accountOperation, assignOutputTo: \.accountData)
                    .inject(from: createDeviceOperation, via: { context, output in
                        let (privateKey, device) = output

                        context.privateKey = privateKey
                        context.device = device
                    })
                    .reduce()

                saveSettingsOperation.addBlockObserver(
                    OperationBlockObserver(didFinish: { operation in
                        self.completeOperation(accountData: operation.output)
                    })
                )

                return [accountOperation, createDeviceOperation, saveSettingsOperation]
            } ?? []

        var enqueueOperations: [Operation] = [deleteDeviceOperation, deleteSettingsOperation]
            .compactMap { $0 }
        enqueueOperations.append(contentsOf: setupAccountOperations)

        if setupAccountOperations.isEmpty {
            let finishingOperation = BlockOperation()
            finishingOperation.completionBlock = { [weak self] in
                self?.completeOperation(accountData: nil)
            }
            finishingOperation.addDependencies(enqueueOperations)
            enqueueOperations.append(finishingOperation)
        }

        children = enqueueOperations
        operationQueue.addOperations(enqueueOperations, waitUntilFinished: false)
    }

    override func operationDidCancel() {
        operationQueue.cancelAllOperations()
    }

    // MARK: - Private

    private func completeOperation(accountData: StoredAccountData?) {
        guard !isCancelled else {
            finish(completion: .cancelled)
            return
        }

        let errors = children.compactMap { operation -> TunnelManager.Error? in
            let fallibleOperation = operation as? FallibleOperation

            return fallibleOperation?.error as? TunnelManager.Error
        }

        if let error = errors.first {
            finish(completion: .failure(error))
        } else {
            finish(completion: .success(accountData))
        }
    }

    private func getAccountDataOperation()
        -> ResultOperation<StoredAccountData, TunnelManager.Error>?
    {
        switch action {
        case .new:
            return getCreateAccountOperation()

        case .existing(let accountNumber):
            return getExistingAccountOperation(accountNumber: accountNumber)

        case .unset:
            return nil
        }
    }

    private func getCreateAccountOperation()
        -> ResultBlockOperation<StoredAccountData, TunnelManager.Error>
    {
        let operation = ResultBlockOperation<
            StoredAccountData,
            TunnelManager.Error
        >(dispatchQueue: dispatchQueue)

        operation.setExecutionBlock { operation in
            self.logger.debug("Create new account...")

            let task = self.accountsProxy.createAccount(retryStrategy: .default) { completion in
                let mappedCompletion = completion.mapError { error -> TunnelManager.Error in
                    self.logger.error(
                        chainedError: AnyChainedError(error),
                        message: "Failed to create new account."
                    )

                    return .restError(error)
                }

                guard let newAccountData = mappedCompletion.value else {
                    operation.finish(completion: mappedCompletion.assertNoSuccess())
                    return
                }

                self.logger.debug("Created new account.")

                let storedAccountData = StoredAccountData(
                    identifier: newAccountData.id,
                    number: newAccountData.number,
                    expiry: newAccountData.expiry
                )

                operation.finish(completion: .success(storedAccountData))
            }

            operation.addCancellationBlock {
                task.cancel()
            }
        }

        return operation
    }

    private func getExistingAccountOperation(accountNumber: String)
        -> ResultOperation<StoredAccountData, TunnelManager.Error>
    {
        let operation = ResultBlockOperation<StoredAccountData, TunnelManager.Error>(
            dispatchQueue: dispatchQueue
        )

        operation.setExecutionBlock { operation in
            self.logger.debug("Request account data...")

            let task = self.accountsProxy.getAccountData(
                accountNumber: accountNumber,
                retryStrategy: .default
            ) { completion in
                let mappedCompletion = completion.mapError { error -> TunnelManager.Error in
                    self.logger.error(
                        chainedError: AnyChainedError(error),
                        message: "Failed to receive account data."
                    )

                    return .restError(error)
                }

                guard let accountData = mappedCompletion.value else {
                    operation.finish(completion: mappedCompletion.assertNoSuccess())
                    return
                }

                self.logger.debug("Received account data.")

                let storedAccountData = StoredAccountData(
                    identifier: accountData.id,
                    number: accountNumber,
                    expiry: accountData.expiry
                )

                operation.finish(completion: .success(storedAccountData))
            }

            operation.addCancellationBlock {
                task.cancel()
            }
        }

        return operation
    }

    private func getDeleteDeviceOperation(accounNumber: String, deviceIdentifier: String)
        -> ResultBlockOperation<Void, TunnelManager.Error>
    {
        let operation = ResultBlockOperation<Void, TunnelManager.Error>(
            dispatchQueue: dispatchQueue
        )

        operation.setExecutionBlock { operation in
            self.logger.debug("Delete current device...")

            let task = self.devicesProxy.deleteDevice(
                accountNumber: accounNumber,
                identifier: deviceIdentifier,
                retryStrategy: .default
            ) { completion in
                let mappedCompletion = completion.mapError { error -> TunnelManager.Error in
                    self.logger.error(chainedError: error, message: "Failed to delete device.")

                    return .restError(error)
                }

                guard let isDeleted = mappedCompletion.value else {
                    operation.finish(completion: mappedCompletion.assertNoSuccess())
                    return
                }

                if isDeleted {
                    self.logger.debug("Deleted device.")
                } else {
                    self.logger.debug("Device is already deleted.")
                }

                operation.finish(completion: .success(()))
            }

            operation.addCancellationBlock {
                task.cancel()
            }
        }

        return operation
    }

    private func getDeleteSettingsOperation() -> AsyncBlockOperation {
        return AsyncBlockOperation(dispatchQueue: dispatchQueue) { operation in
            // Tell the caller to unsubscribe from VPN status notifications.
            self.interactor.prepareForVPNConfigurationDeletion()

            // Reset tunnel and device state.
            self.interactor.resetTunnelState(to: .disconnected)
            self.interactor.setDeviceState(.loggedOut, persist: true)

            // Finish immediately if tunnel provider is not set.
            guard let tunnel = self.interactor.tunnel else {
                operation.finish()
                return
            }

            // Remove VPN configuration.
            tunnel.removeFromPreferences { error in
                self.dispatchQueue.async {
                    // Ignore error but log it.
                    if let error = error {
                        self.logger.error(
                            chainedError: AnyChainedError(error),
                            message: "Failed to remove VPN configuration."
                        )
                    }

                    self.interactor.setTunnel(nil, shouldRefreshTunnelState: false)

                    operation.finish()
                }
            }
        }
    }

    private func getCreateDeviceOperation()
        -> TransformOperation<StoredAccountData, (PrivateKey, REST.Device), TunnelManager.Error>
    {
        let createDeviceOperation = TransformOperation<
            StoredAccountData,
            (PrivateKey, REST.Device),
            TunnelManager.Error
        >(dispatchQueue: dispatchQueue)

        createDeviceOperation.setExecutionBlock { storedAccountData, operation in
            self.logger.debug("Store last used account.")

            do {
                try SettingsManager.setLastUsedAccount(storedAccountData.number)
            } catch {
                self.logger.error(
                    chainedError: AnyChainedError(error),
                    message: "Failed to store last used account number."
                )
            }

            self.logger.debug("Create device...")

            let privateKey = PrivateKey()

            let request = REST.CreateDeviceRequest(
                publicKey: privateKey.publicKey,
                hijackDNS: false
            )

            let task = self.devicesProxy.createDevice(
                accountNumber: storedAccountData.number,
                request: request,
                retryStrategy: .default
            ) { completion in
                let mappedCompletion = completion
                    .map { device in
                        return (privateKey, device)
                    }
                    .mapError { error -> TunnelManager.Error in
                        self.logger.error(chainedError: error, message: "Failed to create device.")
                        return .restError(error)
                    }

                operation.finish(completion: mappedCompletion)
            }

            operation.addCancellationBlock {
                task.cancel()
            }
        }

        return createDeviceOperation
    }

    private func getSaveSettingsOperation()
        -> TransformOperation<SetAccountResult, StoredAccountData, TunnelManager.Error>
    {
        let saveSettingsOperation = TransformOperation<
            SetAccountResult,
            StoredAccountData,
            TunnelManager.Error
        >(dispatchQueue: dispatchQueue)

        saveSettingsOperation.setExecutionBlock { input in
            self.logger.debug("Saving settings...")

            let device = input.device
            let newDeviceState = DeviceState.loggedIn(
                input.accountData,
                StoredDeviceData(
                    creationDate: device.created,
                    identifier: device.id,
                    name: device.name,
                    hijackDNS: device.hijackDNS,
                    ipv4Address: device.ipv4Address,
                    ipv6Address: device.ipv6Address,
                    wgKeyData: StoredWgKeyData(
                        creationDate: Date(),
                        privateKey: input.privateKey
                    )
                )
            )

            self.interactor.setSettings(TunnelSettingsV2(), persist: true)
            self.interactor.setDeviceState(newDeviceState, persist: true)

            return input.accountData
        }

        return saveSettingsOperation
    }
}
