//
//  ManageDevicesViewController.swift
//  MullvadVPN
//
//  Created by pronebird on 15/07/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import UIKit

protocol ManageDevicesViewControllerDelegate: AnyObject {
    func manageDeviceController(
        _ controller: ManageDevicesViewController,
        shouldRemoveDeviceWithIdentifier: String,
        completionHandler: @escaping (Error?) -> Void
    )
}

class ManageDevicesViewController: UIViewController {
    private let contentView = ManageDevicesContentView(frame: .zero)

    private let devicesProxy = REST.ProxyFactory.shared.createDevicesProxy()

    weak var delegate: ManageDevicesViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(contentView)

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        loadDevices()
    }

    func loadDevices() {
        guard let accountNumber = TunnelManager.shared.deviceState.accountData?.number else { return }

        _ = devicesProxy.getDevices(
            accountNumber: accountNumber,
            retryStrategy: .noRetry) { completion in
                if let devices = completion.value {
                    self.setDevices(devices)
                }
            }
    }

    func setDevices(_ devices: [REST.Device]) {
        for arrangedView in contentView.buttonStackView.arrangedSubviews {
            contentView.buttonStackView.removeArrangedSubview(arrangedView)
        }

        for device in devices {
            let deviceRowView = DeviceRowView()

            deviceRowView.deviceName = device.name
            deviceRowView.removeHandler = { [weak self] in
                self?.removeDevice(identifier: device.id)
            }
        }
    }

    func removeDevice(identifier: String) {
        delegate?.manageDeviceController(self, shouldRemoveDeviceWithIdentifier: identifier) { error in
            // TBD
        }
    }
}

class ManageDevicesContentView: UIView {
    let statusImageView: StatusImageView = {
        let imageView = StatusImageView(style: .failure)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    let titleLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.font = UIFont.systemFont(ofSize: 32)
        textLabel.textColor = .white
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        return textLabel
    }()

    let messageLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.font = UIFont.systemFont(ofSize: 17)
        textLabel.textColor = .white
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        return textLabel
    }()

    let continueButton: AppButton = {
        let button = AppButton(style: .success)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let backButton: AppButton = {
        let button = AppButton(style: .default)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let deviceStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    lazy var buttonStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [continueButton, backButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = UIMetrics.contentLayoutMargins

        let subviewsToAdd = [
            statusImageView, titleLabel, messageLabel, deviceStackView, buttonStackView
        ]
        for subview in subviewsToAdd {
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            statusImageView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            statusImageView.centerXAnchor.constraint(equalTo: centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: statusImageView.bottomAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            deviceStackView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 18),
            deviceStackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            deviceStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            buttonStackView.topAnchor.constraint(equalTo: deviceStackView.bottomAnchor, constant: 18),
            buttonStackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class DeviceRowView: UIView {

    var deviceName: String? {
        didSet {
            textLabel.text = deviceName
        }
    }

    var removeHandler: (() -> Void)?

    let textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = UIFont.systemFont(ofSize: 17)
        textLabel.textColor = .white
        return textLabel
    }()

    let removeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "IconCloseSml"), for: .normal)
        button.imageView?.tintColor = .primaryColor.withAlphaComponent(0.4)
        button.accessibilityLabel = NSLocalizedString(
            "REMOVE_DEVICE_ACCESSIBILITY_LABEL",
            tableName: "ManageDevices",
            value: "Remove device",
            comment: ""
        )
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(textLabel)
        addSubview(removeButton)

        removeButton.addTarget(self, action: #selector(handleButtonTap(_:)), for: .touchUpInside)

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            textLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            textLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            removeButton.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleButtonTap(_ sender: Any?) {
        removeHandler?()
    }
}
