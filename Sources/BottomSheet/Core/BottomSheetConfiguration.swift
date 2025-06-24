//
//  BottomSheetConfiguration.swift
//  BottomSheetDemo
//
//  Created by Mikhail Maslo on 15.08.2022.
//  Copyright © 2022 Joom. All rights reserved.
//

import UIKit

public enum DrawerSize {
    case half
    case full
}

/// A struct representing the configuration for a bottom sheet.
public struct BottomSheetConfiguration {
    public let gestureInterceptView: UIView?
    public var cornerRadius: CGFloat
    public var portraitSize: CGFloat?
    public var landscapeSize: CGFloat?
    public var size: DrawerSize?
    public var dismissible: Bool?
    public var isRTL: Bool

    public init(
        cornerRadius: CGFloat = 10,
        gestureInterceptView: UIView? = nil,
        portraitSize: CGFloat? = nil,
        landscapeSize: CGFloat? = nil,
        size: DrawerSize? = nil,
        dismissible: Bool? = true,
        isRTL: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.gestureInterceptView = gestureInterceptView
        self.portraitSize = portraitSize
        self.landscapeSize = landscapeSize
        self.size = size
        self.dismissible = dismissible
        self.isRTL = isRTL
    }

    public static let `default` = BottomSheetConfiguration(
        cornerRadius: 10,
        gestureInterceptView: nil,
        portraitSize: 0,
        landscapeSize: 0,
        size: .half,
        dismissible: nil
    )
}
