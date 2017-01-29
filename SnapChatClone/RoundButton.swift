//
//  RoundButton.swift
//  SnapClone
//
//  Created by Douglas Spencer on 10/23/16.
//  Copyright © 2016 Douglas Spencer. All rights reserved.
//

import UIKit

@IBDesignable
class RoundButton: UIButton {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        //self.setTitle(LabelText, for: .normal)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        
        UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: .allowUserInteraction, animations: {
            self.transform = CGAffineTransform.identity
        }) { (result) in
            print(result)
        }
        
        super.touchesBegan(touches, with: event)
    }
    
    @IBInspectable var CornerRadius: CGFloat = 0 {
        didSet {
            layer.cornerRadius = CornerRadius
            layer.masksToBounds = CornerRadius > 0
        }
    }
    
    @IBInspectable var borderColor: UIColor? {
        didSet {
            layer.borderColor = borderColor?.cgColor
        }
    }
    
    @IBInspectable var BGColor: UIColor? {
        didSet {
            layer.backgroundColor = BGColor?.cgColor
        }
    }
    
    @IBInspectable var LabelText: String? {
        didSet {
            self.titleLabel?.text = LabelText
        }
    }
}
