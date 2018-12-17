//
//  CustomNavigationView.swift
//  Kommunicate
//
//  Created by Shivam Pokhriyal on 15/11/18.
//

import Foundation
import Applozic
import Kingfisher

protocol NavigationBarCallbacks {
    func backButtonPressed()
}

class ConversationVCNavBar: UIView {
    
    var navigationBarBackgroundColor: UIColor
    var configuration: KMConversationViewConfiguration!
    var delegate: NavigationBarCallbacks!
    
    let backButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "icon_back", in: Bundle.kommunicate, compatibleWith: nil), for: .normal)
        button.isUserInteractionEnabled = true
        return button
    }()

    var profileImage: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "placeholder", in: Bundle.kommunicate, compatibleWith: nil)
        return imageView
    }()
    
    var profileName: UILabel = {
        let label = UILabel()
        label.text = "No Name"
        label.font = UIFont(name: "HelveticaNeue", size: 16) ?? UIFont.systemFont(ofSize: 16)
        label.textColor = UIColor(96, green: 94, blue: 94)
        return label
    }()
    
    lazy var statusIconBackgroundColor: UIView = {
        let view = UIView()
        view.backgroundColor = self.navigationBarBackgroundColor
        return view
    }()
    
    var onlineStatusIcon: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(165, green: 170, blue: 165)
        return view
    }()
    
    var onlineStatusText: UILabel = {
        let label = UILabel()
        label.text = "Offline"
        label.font = UIFont(name: "HelveticaNeue", size: 12) ?? UIFont.systemFont(ofSize: 12)
        label.textColor = UIColor(113, green: 110, blue: 110)
        return label
    }()
    
    lazy var profileView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [self.profileName, self.onlineStatusText])
        stackView.alignment = .fill
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = 2
        return stackView
    }()
    
    required init(navigationBarBackgroundColor: UIColor, delegate: NavigationBarCallbacks,
                  configuration: KMConversationViewConfiguration) {
        self.navigationBarBackgroundColor = navigationBarBackgroundColor
        self.configuration = configuration
        self.delegate = delegate
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: 44))
        setupConstraints()
        configureBackButton()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateView(assignee: ALContact?) {
        guard let contact = assignee else {
            return
        }
        setupProfileImage(contact)
        setupOnlineStatus(contact)
    }
    
    @objc func backButtonClicked(_ sender: UIButton) {
        delegate.backButtonPressed()
    }

    private func setupConstraints() {
        self.addViewsForAutolayout(views: [backButton, profileImage, statusIconBackgroundColor, onlineStatusIcon, profileView])
        
        //Setup constraints
        backButton.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0).isActive = true
        backButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 10).isActive = true
        backButton.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10).isActive = true
        backButton.widthAnchor.constraint(equalToConstant: 20).isActive = true

        profileImage.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 10).isActive = true
        profileImage.topAnchor.constraint(equalTo: self.topAnchor, constant: 5).isActive = true
        profileImage.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5).isActive = true
        profileImage.widthAnchor.constraint(equalToConstant: 35).isActive = true
        profileImage.layer.cornerRadius = 18
        profileImage.clipsToBounds = true
        
        statusIconBackgroundColor.bottomAnchor.constraint(equalTo: profileImage.bottomAnchor, constant: 0).isActive = true
        statusIconBackgroundColor.leadingAnchor.constraint(equalTo: profileImage.trailingAnchor, constant: -10).isActive = true
        statusIconBackgroundColor.widthAnchor.constraint(equalToConstant: 12).isActive = true
        statusIconBackgroundColor.heightAnchor.constraint(equalToConstant: 12).isActive = true
        statusIconBackgroundColor.layer.cornerRadius = 6
        statusIconBackgroundColor.clipsToBounds = true
        
        onlineStatusIcon.centerXAnchor.constraint(equalTo: statusIconBackgroundColor.centerXAnchor).isActive = true
        onlineStatusIcon.centerYAnchor.constraint(equalTo: statusIconBackgroundColor.centerYAnchor).isActive = true
        onlineStatusIcon.widthAnchor.constraint(equalToConstant: 10).isActive = true
        onlineStatusIcon.heightAnchor.constraint(equalToConstant: 10).isActive = true
        onlineStatusIcon.layer.cornerRadius = 5
        onlineStatusIcon.clipsToBounds = true
        
        profileView.leadingAnchor.constraint(equalTo: profileImage.trailingAnchor, constant: 5).isActive = true
        profileView.topAnchor.constraint(equalTo: profileImage.topAnchor).isActive = true
        profileView.bottomAnchor.constraint(equalTo: profileImage.bottomAnchor).isActive = true
        profileView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        
        // Add target to back button.
        backButton.addTarget(self, action: #selector(backButtonClicked(_:)), for: .touchUpInside)
    }
    
    private func configureBackButton() {
        if configuration.hideBackButton {
            backButton.isHidden = true
        }
        guard let image = configuration.imageForBackButton else {
            return
        }
        backButton.setImage(image, for: .normal)
    }
    
    private func setupProfileImage(_ contact: ALContact) {
        let placeHolder = UIImage(named: "placeholder", in: Bundle.kommunicate, compatibleWith: nil)
        var url: URL?
        if let imageUrl = contact.contactImageUrl {
            url = URL(string: imageUrl)
        }
        if let downloadURL = url {
            let resource = ImageResource(downloadURL: downloadURL, cacheKey: downloadURL.absoluteString)
            self.profileImage.kf.setImage(with: resource, placeholder: placeHolder, options: nil, progressBlock: nil, completionHandler: nil)
        } else {
            self.profileImage.image = placeHolder
        }
        profileName.text = contact.getDisplayName()
    }
    
    private func setupOnlineStatus(_ contact: ALContact) {
        if contact.connected {
            onlineStatusText.text = "Online"
            onlineStatusIcon.backgroundColor = UIColor(28, green: 222, blue: 20)
        } else {
            onlineStatusText.text = "Offline"
            onlineStatusIcon.backgroundColor = UIColor(165, green: 170, blue: 165)
        }
    }
    
}
