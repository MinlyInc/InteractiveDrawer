//
//  BottomSheetPresentationController.swift
//  BottomSheet
//
//  Created by Mikhail Maslo on 14.11.2021.
//  Copyright © 2021 Joom. All rights reserved.
//

import Combine
import UIKit

public enum BottomSheetOrientation {
    case portrait
    case landscape
    public static let `default`: BottomSheetOrientation = .portrait
}

public protocol ScrollableBottomSheetPresentedController: AnyObject {
    var scrollView: UIScrollView? { get }
}

public final class BottomSheetPresentationController: UIPresentationController {
    // MARK: - Nested

    private enum State {
        case dismissed
        case presenting
        case presented
        case dismissing
    }

    // MARK: - Public properties

    var interactiveTransition: UIViewControllerInteractiveTransitioning? {
        interactionController
    }

    // MARK: - Private properties

    private var state: State = .dismissed
    private var isInteractiveTransitionCanBeHandled: Bool {
        isDragging && !isNavigationTransitionInProgress
    }

    private var isDragging = false {
        didSet {
            if isDragging {
                assert(interactionController == nil)
            }
        }
    }

    private var isNavigationTransitionInProgress = false {
        didSet {
            assert(interactionController == nil)
        }
    }

    private var overlayTranslation: CGFloat = 0
    private var scrollViewTranslation: CGFloat = 0
    private var lastContentOffsetBeforeDragging: CGPoint = .zero
    private var didStartDragging = false
    private var currentOrientation: BottomSheetOrientation = .default

    private var interactionController: UIPercentDrivenInteractiveTransition?
    private weak var trackedScrollView: UIScrollView?

    private var cachedInsets: UIEdgeInsets = .zero

    private let dismissalHandler: BottomSheetModalDismissalHandler
    private var configuration: BottomSheetConfiguration

    // MARK: - Init

    public init(
        presentedViewController: UIViewController,
        presentingViewController: UIViewController?,
        dismissalHandler: BottomSheetModalDismissalHandler,
        configuration: BottomSheetConfiguration
    ) {
        self.dismissalHandler = dismissalHandler
        self.configuration = configuration
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
    }

    // MARK: - Setup

    private func setupGesturesForPresentedView() {
        setupPanGesture(for: presentedView)
    }

    private func setupPanGesture(for view: UIView?) {
        guard let view = view else {
            return
        }

        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        view.addGestureRecognizer(panRecognizer)
        panRecognizer.delegate = self
    }

    private func setupScrollTrackingIfNeeded() {
        if let navigationController = presentedViewController as? UINavigationController {
            navigationController.multicastingDelegate.addDelegate(self)

            if let topViewController = navigationController.topViewController {
                trackScrollView(inside: topViewController)
            }
        } else {
            trackScrollView(inside: presentedViewController)
        }
    }

    private func removeScrollTrackingIfNeeded() {
        trackedScrollView?.multicastingDelegate.removeDelegate(self)
        trackedScrollView = nil
    }

    // MARK: - UIPresentationController

    public override func presentationTransitionWillBegin() {
        state = .presenting
    }

    public override func presentationTransitionDidEnd(_ completed: Bool) {
        if completed {
            setupGesturesForPresentedView()
            setupScrollTrackingIfNeeded()
            state = .presented
        } else {
            state = .dismissed
        }
    }

    public override func dismissalTransitionWillBegin() {
        state = .dismissing
    }

    public override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            removeScrollTrackingIfNeeded()

            state = .dismissed
            dismissalHandler.didEndDismissal()
        } else {
            state = .presented
        }
    }

    public override var frameOfPresentedViewInContainerView: CGRect {
        targetFrameForPresentedView()
    }

    public override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()

        updatePresentedViewSize(animated: true)
    }

    public override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        updatePresentedViewSize(animated: true)
    }

    // MARK: - Interactive Dismissal

    @objc
    private func handlePanGesture(_ panGesture: UIPanGestureRecognizer) {
        switch panGesture.state {
        case .began:
            processPanGestureBegan(panGesture)
        case .changed:
            processPanGestureChanged(panGesture)
        case .ended:
            processPanGestureEnded(panGesture)
        case .cancelled:
            processPanGestureCancelled(panGesture)
        default:
            break
        }
    }

    private func processPanGestureBegan(_ panGesture: UIPanGestureRecognizer) {
        startInteractiveTransition()
    }

    private func startInteractiveTransition() {
        interactionController = UIPercentDrivenInteractiveTransition()

        presentedViewController.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            if self.presentingViewController.presentedViewController !== self.presentedViewController {
                self.dismissalHandler.performDismissal(animated: true)
            }
        }
    }

    private func processPanGestureChanged(_ panGesture: UIPanGestureRecognizer) {
        let translation = panGesture.translation(in: nil)
        updateInteractionControllerProgress(verticalTranslation: translation.y)
    }

    private func updateInteractionControllerProgress(verticalTranslation: CGFloat) {
        guard let presentedView = presentedView else {
            return
        }

        let progress = verticalTranslation / presentedView.bounds.height
        interactionController?.update(progress)
    }

    private func processPanGestureEnded(_ panGesture: UIPanGestureRecognizer) {
        let velocity = panGesture.velocity(in: presentedView)
        let translation = panGesture.translation(in: presentedView)
        endInteractiveTransition(verticalVelocity: velocity.y, verticalTranslation: translation.y)
    }

    private func endInteractiveTransition(verticalVelocity: CGFloat, verticalTranslation: CGFloat) {
        guard let presentedView = presentedView else {
            return
        }

        let deceleration = 800.0 * (verticalVelocity > 0 ? -1.0 : 1.0)
        let finalProgress = (verticalTranslation - 0.25 * verticalVelocity * verticalVelocity / CGFloat(deceleration))
            / presentedView.bounds.height
        let isThresholdPassed = finalProgress < 0.5

        endInteractiveTransition(isCancelled: isThresholdPassed)
    }

    private func processPanGestureCancelled(_ panGesture: UIPanGestureRecognizer) {
        endInteractiveTransition(isCancelled: true)
    }

    private func endInteractiveTransition(isCancelled: Bool) {
        if isCancelled {
            interactionController?.cancel()
        } else if !dismissalHandler.canBeDismissed {
            interactionController?.cancel()
        } else {
            interactionController?.finish()
        }
        interactionController = nil
    }

    // MARK: - Private

    private func applyStyle() {
        guard presentedViewController.isViewLoaded else {
            assertionFailure()
            return
        }
        presentedViewController.view.clipsToBounds = true
        presentedViewController.view.layer.cornerRadius = configuration.cornerRadius
        presentedViewController.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    private func setCurrentOrientation() {
        let currentInterfaceOrientation = getCurrentInterfaceOrientation()
        // Update configuration if necessary based on the interface orientation
        if currentInterfaceOrientation.isLandscape {
            currentOrientation = .landscape
        } else {
            currentOrientation = .portrait
        }
    }

    private func getCurrentInterfaceOrientation() -> UIInterfaceOrientation {
        if #available(iOS 13.0, *) {
            if let windowScene = containerView?.window?.windowScene {
                return windowScene.interfaceOrientation
            }
        }
        return UIApplication.shared.statusBarOrientation
    }

    private func targetFrameForPresentedView() -> CGRect {
        guard let containerView = containerView else {
            return .zero
        }
        setCurrentOrientation()
        let containerWidth = containerView.bounds.width
        let containerHeight = containerView.bounds.height
        let windowInsets = presentedView?.window?.safeAreaInsets ?? cachedInsets
        let preferredHeight = presentedViewController.preferredContentSize.height + windowInsets.bottom
        let preferredWidth = presentedViewController.preferredContentSize.width + windowInsets.bottom
        let width: CGFloat
        let height: CGFloat
        let xPosition: CGFloat
        let yPosition: CGFloat
        if currentOrientation == .portrait {
            width = containerWidth
            height = min(preferredHeight, UIScreen.main.bounds.height)
            xPosition = 0
            yPosition = UIScreen.main.bounds.height - height
        } else {
            width = min(preferredWidth, UIScreen.main.bounds.width)
            height = containerHeight
            xPosition = configuration.isRTL ?  0 : UIScreen.main.bounds.width - width
            yPosition = 0
        }

        return CGRect(
            x: xPosition.pixelCeiled,
            y: yPosition.pixelCeiled,
            width: width.pixelCeiled,
            height: height.pixelCeiled
        )
    }

    private func updatePresentedViewSize(animated: Bool = true) {
        guard let presentedView = presentedView, let containerView = containerView else {
            return
        }
        let targetFrame = targetFrameForPresentedView()

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                containerView.frame = targetFrame
                presentedView.frame = containerView.bounds
                containerView.layoutIfNeeded()
            }, completion: nil)
        } else {
            containerView.frame = targetFrame
            presentedView.frame = containerView.bounds
            containerView.layoutIfNeeded()
            presentedView.layoutIfNeeded()
        }
        applyStyle()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { _ in
            self.updatePresentedViewSize()
        }
    }

    @discardableResult
    private func dismissIfPossible() -> Bool {
        let canBeDismissed = state == .presented && dismissalHandler.canBeDismissed

        if canBeDismissed {
            dismissalHandler.performDismissal(animated: true)
        }

        return canBeDismissed
    }
}

extension BottomSheetPresentationController: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let interceptView = configuration.gestureInterceptView else {
            defaultScrollHandling(scrollView)
            return
        }
        let touchPoint = scrollView.panGestureRecognizer.location(in: interceptView)
        if interceptView.bounds.contains(touchPoint) {
            return
        }
        defaultScrollHandling(scrollView)
    }

    private func defaultScrollHandling(_ scrollView: UIScrollView) {
        if
            !scrollView.isContentOriginInBounds,
            scrollView.contentSize.height.isAlmostEqual(to: scrollView.frame.height - scrollView.adjustedContentInset.verticalInsets)
        {
            scrollView.bounds.origin.y = -scrollView.adjustedContentInset.top
        }

        let previousTranslation = scrollViewTranslation
        scrollViewTranslation = scrollView.panGestureRecognizer.translation(in: scrollView).y

        didStartDragging = shouldDragOverlay(following: scrollView)
        if didStartDragging {
            startInteractiveTransitionIfNeeded()
            overlayTranslation += scrollViewTranslation - previousTranslation
            scrollView.bounds.origin.y = -scrollView.adjustedContentInset.top
            updateInteractionControllerProgress(verticalTranslation: overlayTranslation)
        } else {
            lastContentOffsetBeforeDragging = scrollView.panGestureRecognizer.translation(in: scrollView)
        }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isDragging = true
    }

    public func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        if didStartDragging {
            let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
            let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
            endInteractiveTransition(
                verticalVelocity: velocity.y,
                verticalTranslation: translation.y - lastContentOffsetBeforeDragging.y
            )
        } else {
            endInteractiveTransition(isCancelled: true)
        }

        overlayTranslation = 0
        scrollViewTranslation = 0
        lastContentOffsetBeforeDragging = .zero
        didStartDragging = false
        isDragging = false
    }

    private func startInteractiveTransitionIfNeeded() {
        guard interactionController == nil else {
            return
        }

        startInteractiveTransition()
    }

    private func shouldDragOverlay(following scrollView: UIScrollView) -> Bool {
        guard scrollView.isTracking, isInteractiveTransitionCanBeHandled else {
            return false
        }

        if let percentComplete = interactionController?.percentComplete {
            if percentComplete.isAlmostEqual(to: 0) {
                return scrollView.isContentOriginInBounds && scrollView.scrollsDown
            }

            return true
        } else {
            return scrollView.isContentOriginInBounds && scrollView.scrollsDown
        }
    }
}

extension BottomSheetPresentationController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }

        let translation = panGesture.translation(in: presentedView)
        return state == .presented && translation.y > 0
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if otherGestureRecognizer === trackedScrollView?.panGestureRecognizer {
            return true
        }

        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let interceptView = configuration.gestureInterceptView {
            let touchLocation = touch.location(in: interceptView)

            if interceptView.bounds.contains(touchLocation) {
                return false
            }
        }

        return !isNavigationTransitionInProgress
    }
}

extension BottomSheetPresentationController: UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        trackScrollView(inside: viewController)

        isNavigationTransitionInProgress = false
    }

    public func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        isNavigationTransitionInProgress = true
    }

    private func trackScrollView(inside viewController: UIViewController) {
        guard
            let scrollableViewController = viewController as? ScrollableBottomSheetPresentedController,
            let scrollView = scrollableViewController.scrollView
        else {
            return
        }

        trackedScrollView?.multicastingDelegate.removeDelegate(self)
        scrollView.multicastingDelegate.addDelegate(self)
        trackedScrollView = scrollView
    }
}

extension BottomSheetPresentationController: UIViewControllerAnimatedTransitioning {
    public func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    public func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let sourceViewController = transitionContext.viewController(forKey: .from),
            let destinationViewController = transitionContext.viewController(forKey: .to),
            let sourceView = sourceViewController.view,
            let destinationView = destinationViewController.view
        else {
            return
        }

        let isPresenting = destinationViewController.isBeingPresented
        let presentedView = isPresenting ? destinationView : sourceView
        let containerView = transitionContext.containerView

        if isPresenting {
            containerView.addSubview(destinationView)
        }

        sourceView.layoutIfNeeded()
        destinationView.layoutIfNeeded()
        let finalFrame = targetFrameForPresentedView()
        let offscreenFrame = CGRect(
            origin: CGPoint(x: finalFrame.origin.x, y: containerView.frame.height),
            size: finalFrame.size
        )

        if isPresenting {
            presentedView.frame = offscreenFrame
        }

        applyStyle()

        let animations = {
            if isPresenting {
                presentedView.frame = finalFrame
            } else {
                presentedView.frame.origin.y = containerView.frame.height
            }
        }

        let completion = { (completed: Bool) in
            if !isPresenting, completed, !transitionContext.transitionWasCancelled {
                presentedView.removeFromSuperview()
            }
            transitionContext.completeTransition(completed && !transitionContext.transitionWasCancelled)
        }
        let options: UIView.AnimationOptions = transitionContext.isInteractive ? .curveLinear : .curveEaseInOut
        let transitionDurationValue = transitionDuration(using: transitionContext)
        UIView.animate(withDuration: transitionDurationValue, delay: 0, options: options, animations: animations, completion: completion)
    }

    public func animationEnded(_ transitionCompleted: Bool) {}
}

private extension UIScrollView {
    var scrollsUp: Bool {
        panGestureRecognizer.velocity(in: nil).y < 0
    }

    var scrollsDown: Bool {
        !scrollsUp
    }

    var isContentOriginInBounds: Bool {
        contentOffset.y <= -adjustedContentInset.top
    }
}
