//
//  NIActionSheet.swift
//  Pods
//
//  Created by Jim Boyd on 8/10/16.
//  See also: https://www.societas.mobi/2015/11/14/uialertview-deprecated-in-ios9-our-workaround/
//

import UIKit

@objc public protocol NIActionSheetDelegate: NSObjectProtocol {
    // Called when a button is clicked. The view will be automatically dismissed after this call returns
    @objc optional func actionSheet(_ actionSheet: NIActionSheet, clickedButtonAt buttonIndex: Int)
	
	// Called when we cancel a view (eg. the user clicks the Home button). This is not called when the user clicks the cancel button.
    // If not defined in the delegate, we simulate a click in the cancel button
    @objc optional func actionSheetCancel(_ actionSheet: NIActionSheet)
	
	@objc optional func willPresent(_ actionSheet: NIActionSheet) // before animation and showing view
	
	@objc optional func didPresent(_ actionSheet: NIActionSheet) // after animation
	
	@objc optional func actionSheet(_ actionSheet: NIActionSheet, willDismissWithButtonIndex buttonIndex: Int) // before animation and hiding view
    @objc optional func actionSheet(_ actionSheet: NIActionSheet, didDismissWithButtonIndex buttonIndex: Int) // after animation
}

public class NIActionSheet: NSObject {
    /**
     Holds the alert controller actually used to display the alert.
     */
	@objc public var myAlertController: UIAlertController?
	
	/* if the delegate does not implement -actionSheetCancel:, we pretend this button	 was clicked on. default is -1 */
	@objc public var cancelButtonIndex: Int = -1
	
	/* sets destructive (red) button. -1 means none set. default is -1. ignored if only one button */
	@objc public var destructiveButtonIndex: Int = -1
	
	/* -1 if no otherButtonTitles or initWithTitle:... not used */
	@objc public var firstOtherButtonIndex: Int = -1
	
	@objc public var numberOfButtons: Int {
		return self.index
	}
	
	@objc public var title: String? {
		get {
			return myAlertController?.title
		}
		set {
			myAlertController?.title = newValue
		}
	}
	
    /**
     The delegate if one specified. This will be called with the button pressed
     */
    @objc public weak var delegate: NIActionSheetDelegate?
    var index: Int = 0

	@objc public init(title: String?, delegate: NIActionSheetDelegate?, cancelButtonTitle: String?, destructiveButtonTitle: String?, otherButtonTitles: [String]? = nil) {
		
		super.init()

        self.myAlertController = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
		
		if let cancelButtonTitle = cancelButtonTitle {
			self.cancelButtonIndex = self.index
			self.index += 1
			
			let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel, handler: { action in
				self.clicked(self.cancelButtonIndex)
			})
			
			self.myAlertController?.addAction(cancelAction)
		}
		
		if let destructiveButtonTitle = destructiveButtonTitle {
			self.destructiveButtonIndex = self.index
			self.index += 1
			
			let destructiveAction = UIAlertAction(title: destructiveButtonTitle, style: .destructive, handler: { action in
				self.clicked(self.destructiveButtonIndex)
			})
			
			self.myAlertController?.addAction(destructiveAction)
		}
		
		if let otherButtonTitles = otherButtonTitles {
			self.firstOtherButtonIndex = self.index
			
			for title in otherButtonTitles {
				// Create a button with the argument

				let defaultAction = UIAlertAction(title: title, style: .default, handler: { action in
					self.clicked(self.index)
				})

				myAlertController?.addAction(defaultAction)
				self.index += 1
			}
		}

        // set the delegate
        self.delegate = delegate
    }

	@objc public private(set) var isVisible = false
	
	@objc public func show() {
        show(UIApplication.shared.keyWindow?.rootViewController)
    }

    @objc public func show(_ v: UIViewController?) {
        if let v = v, let aController = myAlertController {
			self.delegate?.willPresent?(self)
			v.present(aController, animated: true) {
				self.delegate?.didPresent?(self)
				self.isVisible = true
			}
       	}
    }
	
	// hides alert sheet or popup. use this method when you need to explicitly dismiss the alert.
	// it does not need to be called if the user presses on a button
	@objc public func dismiss(withClickedButtonIndex buttonIndex: Int, animated: Bool) {
		self.clicked(buttonIndex, dismissAnimated: animated)
	}

	@discardableResult
	@objc public func addButton(withTitle title: String) -> Int {
		let defaultAction = UIAlertAction(title: title, style: .default, handler: { action in
			self.clicked(self.index)
		})
		
		myAlertController?.addAction(defaultAction)
		
		defer {
			self.index += 1
		}

		return self.index
	}
	
	@objc public func buttonTitle(at buttonIndex: Int) -> String? {
		 return self.myAlertController?.actions[buttonIndex].title
	}

    /**
     Method to call when a button is clicked. If the delegate is set, the delegate's alertView:(NIActionSheet *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex;
     
     is called with the index of the button. If the delegate is not set, nothing is done.
     */
    func clicked(_ i: Int, dismissAnimated animated: Bool = true) {
		if (i == self.cancelButtonIndex) {
			delegate?.actionSheetCancel?(self)
		}
		
		delegate?.actionSheet?(self, clickedButtonAt: i)
		delegate?.actionSheet?(self, willDismissWithButtonIndex: i)
		
		self.myAlertController?.dismiss(animated: animated) {
			self.delegate?.actionSheet?(self, didDismissWithButtonIndex: i)
			self.isVisible = false
		}
    }
}
