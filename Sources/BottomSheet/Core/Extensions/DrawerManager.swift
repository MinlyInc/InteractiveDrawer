//
//  DrawerManager.swift
//  BottomSheetDemo
//
//  Created by Mahmoud on 07/10/2024.
//  Copyright © 2024 Joom. All rights reserved.
//

import UIKit

/// An enum indicates wheather opening a new Drawer is for orientation changes or user action.
private enum OpenState {
    case orienationChanges
    case regular
}

public enum DrawerState {
    case opened
    case closed
}

public protocol DrawerStateDelegate: AnyObject {
    func drawerStateDidChange(to state: DrawerState)
}

public class DrawerManager {
    private weak var parentController: UIViewController?
    private var activeDrawer: UIViewController?
    private var currentConfiguration = BottomSheetConfiguration()
    private var openState: OpenState = .regular
    private var dismissCompletion: (() -> Void)?
    public weak var drawerStateDelegate: DrawerStateDelegate?
    public var drawerState: DrawerState = .closed {
        didSet {
            drawerStateDelegate?.drawerStateDidChange(to: drawerState)
        }
    }

    /// Initializes DrawerManager with a parent UIViewController
    public init(parentController: UIViewController) {
        self.parentController = parentController
    }

    /// Handles changes in device orientation and updates the drawer accordingly.
    /// - Note: This should be triggered when the device orientation changes.
    public func orientationDidChange() {
        guard let activeDrawer = activeDrawer else { return }
        openState = .orienationChanges
        drawerState = .closed
        openDrawer(viewController: activeDrawer, configuration: currentConfiguration, dismissCompletion: dismissCompletion)
    }

    public func setDrawerSize(
        portraitSize: CGFloat? = nil,
        landscapeSize: CGFloat? = nil,
        size: DrawerSize? = nil
    ) {
        if let portraitSize = portraitSize {
            currentConfiguration.portraitSize = portraitSize
        }
        if let landscapeSize = landscapeSize {
            currentConfiguration.landscapeSize = landscapeSize
        }

        let screenHeight = UIScreen.main.bounds.height
        let screenWidth = UIScreen.main.bounds.width
        if let size = size {
            let calculatedPortraitSize: CGFloat = size == .full ? screenHeight : screenHeight / 2
            let calculatedLandscapeSize: CGFloat = size == .full ? screenWidth : screenWidth / 2
            currentConfiguration.portraitSize = calculatedPortraitSize
            currentConfiguration.landscapeSize = calculatedLandscapeSize
        }
        if currentConfiguration.portraitSize == 0 {
            currentConfiguration.portraitSize = screenHeight / 2
        }
        if currentConfiguration.landscapeSize == 0 {
            currentConfiguration.landscapeSize = screenWidth / 2
        }
    }

    /// Opens a drawer with the specified configuration.
    /// - Parameters:
    ///   - viewController: The view controller to present as a drawer.
    ///   - size: The drawer size (only used if no views and no custom height are provided).
    ///   - configuration: The custom configuration for the bottom sheet (optional with default values).
    ///   - dismissCompletion: Optional closure called when the drawer is dismissed.
    public func presentDrawer(
        from parentController: UIViewController,
        viewController: UIViewController,
        configuration: BottomSheetConfiguration,
        dismissCompletion: (() -> Void)? = nil
    ) {
        currentConfiguration = configuration
        self.parentController = parentController
        setDrawerSize(
            portraitSize: configuration.portraitSize,
            landscapeSize: configuration.landscapeSize,
            size: configuration.size
        )
        self.dismissCompletion = dismissCompletion
        openDrawer(viewController: viewController, configuration: configuration, dismissCompletion: dismissCompletion)
    }

    /// Presents the drawer with the specified configuration.
    /// - Parameters:
    ///   - viewController: The view controller to present as a drawer.
    ///   - configuration: The custom configuration for the bottom sheet.
    ///   - dismissCompletion: Optional closure called when the drawer is dismissed.
    private func openDrawer(
        viewController: UIViewController,
        configuration: BottomSheetConfiguration,
        dismissCompletion: (() -> Void)?
    ) {
        guard let parentController = parentController else { return }

        closeActiveDrawer(animated: false, disposeDrawer: true)
        activeDrawer = viewController
        refreshSize(portraitSize: configuration.portraitSize, landscapeSize: configuration.landscapeSize)
        drawerState = .opened
        parentController.presentBottomSheet(
            viewController: viewController,
            configuration: BottomSheetConfiguration(
                cornerRadius: configuration.cornerRadius,
                gestureInterceptView: configuration.gestureInterceptView,
                dismissible: configuration.dismissible
            ),
            canBeDismissed: { configuration.dismissible ?? true },
            dismissCompletion: {
                if self.openState == .regular {
                    self.closeActiveDrawer(animated: true, disposeDrawer: true)
                } else {
                    self.closeActiveDrawer(animated: false, disposeDrawer: false)
                    self.openState = .regular
                }
            }
        )
    }

    /// Updates the active drawer with a new size based on the current orientation.
    /// - Parameters:
    ///   - portraitSize: The height of the drawer when in portrait orientation. If nil, the current active portrait size is used.
    ///   - landscapeSize: The height of the drawer when in landscape orientation. If nil, the current active landscape size is used.
    ///   - size: The drawer size, used as a reference for custom sizing if needed.
    public func refreshSize(
        portraitSize: CGFloat? = nil,
        landscapeSize: CGFloat? = nil
    ) {
        guard let activeDrawer = activeDrawer else { return }

        if let newPortraitSize = portraitSize {
            currentConfiguration.portraitSize = newPortraitSize
            activeDrawer.preferredContentSize.height = currentConfiguration.portraitSize ?? UIScreen.main.bounds.height / 2
        }

        if let newLandscapeSize = landscapeSize {
            currentConfiguration.landscapeSize = newLandscapeSize
            activeDrawer.preferredContentSize.width = currentConfiguration.landscapeSize ?? UIScreen.main.bounds.width / 2
        }
    }

    /// Closes the currently active drawer, if any.
    public func closeActiveDrawer(animated: Bool, disposeDrawer: Bool = true) {
        guard let activeDrawer = activeDrawer else { return }
        activeDrawer.dismiss(animated: animated) {
            if disposeDrawer {
                self.drawerState = .closed
                self.activeDrawer = nil
                self.dismissCompletion?()
            }
        }
    }
}
