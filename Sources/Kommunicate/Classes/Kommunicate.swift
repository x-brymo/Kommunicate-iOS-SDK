//
//  Kommunicate.swift
//  Kommunicate
//
//  Created by Mukesh Thawani on 07/03/18.
//

import Foundation
import UIKit
import ApplozicCore
import ApplozicSwift
#if canImport(RichMessageKit)
    import RichMessageKit
    public typealias KMStyle = RichMessageKit.Style
#else
    public typealias KMStyle = ApplozicSwift.Style
#endif

var TYPE_CLIENT : Int16 = 0
var TYPE_APPLOZIC : Int16 = 1
var TYPE_FACEBOOK : Int16 = 2

var APNS_TYPE_DEVELOPMENT : Int16 = 0
var APNS_TYPE_DISTRIBUTION : Int16 = 1

public typealias KMUser = ALUser
public typealias KMUserDefaultHandler = ALUserDefaultsHandler
public typealias KMPushNotificationService = ALPushNotificationService
public typealias KMAppLocalNotification = ALAppLocalNotifications
public typealias KMDbHandler = ALDBHandler
public typealias KMRegisterUserClientService = ALRegisterUserClientService
public typealias KMConfiguration = ALKConfiguration
public typealias KMMessageStyle = ALKMessageStyle
public typealias KMBaseNavigationViewController = ALKBaseNavigationViewController
public typealias KMChatBarConfiguration = ALKChatBarConfiguration
public typealias KMCustomEventHandler = ALKCustomEventHandler

let faqIdentifier =  11223346

enum KMLocalizationKey {
    static let noName = "NoName"
}

@objc
open class Kommunicate: NSObject,Localizable, KMPreChatFormViewControllerDelegate {

    //MARK: - Public properties

    /// Returns true if user is already logged in.
    @objc open class var isLoggedIn: Bool {
        return KMUserDefaultHandler.isLoggedIn()
    }

    /**
     Default configuration which defines the behaviour of UI components.
     It's used while initializing any UI component or in
     `KMPushNotificationHandler`.
     - Note: This can be changed from outside if you want to enable or
     disable some features but avoid initializing a new `KMConfiguration`
     object as we have set some properties in the default configuration object
     which shouldn't be disabled. So use the `defaultConfiguration` and change
     it accordingly.
     */
    public static var defaultConfiguration: KMConfiguration = {
        var config = KMConfiguration()

        config.isTapOnNavigationBarEnabled = false
        config.isProfileTapActionEnabled = false
        var navigationItemsForConversationList = [ALKNavigationItem]()
        let faqItem = ALKNavigationItem(identifier: faqIdentifier, text:  NSLocalizedString("FaqTitle", value: "FAQ", comment: ""))
        navigationItemsForConversationList.append(faqItem)
        var navigationItemsForConversationView = [ALKNavigationItem]()
        navigationItemsForConversationView.append(faqItem)
        config.navigationItemsForConversationList = navigationItemsForConversationList
        config.navigationItemsForConversationView = navigationItemsForConversationView
        config.disableSwipeInChatCell = true
        config.chatBar.optionsToShow = .some([.camera, .location, .gallery, .video, .document])
        return config
    }()

    /// Configuration which defines the behavior of ConversationView components.
    public static var kmConversationViewConfiguration = KMConversationViewConfiguration()

    public static let shared = Kommunicate()
    public static var presentingViewController = UIViewController()
    public static var leadArray = [LeadCollectionFields]()

    public enum KommunicateError: Error {
        case notLoggedIn
        case conversationNotPresent
        case conversationCreateFailed
        case teamNotPresent
        case conversationUpdateFailed
        case appSettingsFetchFailed
    }

    //MARK: - Private properties

    private static var applicationId = ""

    private var pushNotificationTokenData: Data? {
        didSet {
            updateToken()
        }
    }

    static var applozicClientType: ApplozicClient.Type = ApplozicClient.self

    public override init() {
        super.init()
    }

    //MARK: - Public methods


    /**
     Setup an App ID. It will be used for all Kommunicate related requests.

     - NOTE: If the App ID is modified then make sure to log out and log in.

     - Parameters:
     - applicationId: App ID that needs to be set up.
     */
    @objc open class func setup(applicationId: String) {
        guard !applicationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            assertionFailure("Kommunicate App ID: Empty value passed")
            return
        }
        guard KMUserDefaultHandler.isAppIdEmpty ||
            KMUserDefaultHandler.matchesCurrentAppId(applicationId) else {
                assertionFailure("Kommunicate App ID changed: log out and log in again")
                return
        }
        self.applicationId = applicationId
        ALUserDefaultsHandler.setApplicationKey(applicationId)
        Kommunicate.shared.defaultChatViewSettings()
        Kommunicate.shared.setupDefaultStyle()
    }

    /**
     Registers a new user, if it's already registered then user will be logged in.

     - Parameters:
     - kmUser: A KMUser object which contains user details.
     - completion: The callback with registration response and error.
     */
    @objc open class func registerUser(
        _ kmUser: KMUser,
        completion : @escaping (_ response: ALRegistrationResponse?, _ error: NSError?) -> Void) {
        let validationError = validateUserData(user: kmUser)
        guard validationError == nil else {
            print("Error while registering the user to Kommunicate: ", validationError!.localizedDescription)
            completion(nil, validationError)
            return
        }
        let registerUserClientService: ALRegisterUserClientService = ALRegisterUserClientService()
        registerUserClientService.initWithCompletion(kmUser, withCompletion: { (response, error) in
            if (error != nil)
            {
                print("Error while registering the user to Kommunicate")
                let errorPass = NSError(domain:"Error while registering the user to Kommunicate", code:0, userInfo:nil)
                completion(response, errorPass as NSError?)
            }
            else if(!(response?.isRegisteredSuccessfully())!)
            {
                let errorPass = NSError(domain:"Invalid Password", code:0, userInfo:nil)
                print("Error while registering the user to Kommunicate: ", errorPass.localizedDescription)
                completion(response , errorPass as NSError?)
            }
            else
            {
                print("Registered the user to Kommunicate")
                let kmAppSetting = KMAppSettingService()
                kmAppSetting.appSetting { (result) in
                    switch result {
                    case .success(let appSetting):
                        DispatchQueue.main.async {
                            kmAppSetting.updateAppsettings(chatWidgetResponse: appSetting.chatWidget)
                            KMAppUserDefaultHandler.shared.isCSATEnabled
                                = appSetting.collectFeedback ?? false
                            completion(response , error as NSError?)
                        }
                    case .failure( _) :
                        DispatchQueue.main.async {
                            completion(response , error as NSError?)
                        }
                    }
                }
            }
        })
    }

    /// Logs out the current logged in user and clears all the cache.
    open class func logoutUser(completion: @escaping (Result<String, KMError>) -> ()) {
        let applozicClient = applozicClientType.init(applicationKey: KMUserDefaultHandler.getApplicationKey())
        applozicClient?.logoutUser(completion: { (error, apiResponse) in
            Kommunicate.shared.clearUserDefaults()
            guard error == nil else {
                completion(.failure(KMError.api(error)))
                return
            }
            completion(.success("success"))
        })
    }

    /// Creates a new conversation with the details passed.
    /// - Parameter conversation: An instance of `KMConversation` object.
    /// - Parameter completion: If successful the success callback will have a conversationId else it will be KMConversationError on failure.
    open class func createConversation (
        conversation: KMConversation = KMConversationBuilder().build(),
        completion: @escaping (Result<String, KMConversationError>) -> ()) {
        
              guard ALDataNetworkConnection.checkDataNetworkAvailable() else {
            completion(.failure(KMConversationError.internet))
            return
        }

        if let conversationTitle = conversation.conversationTitle, conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("The conversation title should not be empty")
            completion(.failure(KMConversationError.invalidTitle))
            return
        }

        let service = KMConversationService()
        let appSettingsService = KMAppSettingService()
        if KMUserDefaultHandler.isLoggedIn() {
            var allAgentIds = conversation.agentIds
            var allBotIds = ["bot"] // Default bot that should be added everytime.
            if let botIds = conversation.botIds { allBotIds.append(contentsOf: botIds) }

            appSettingsService.appSetting {
                result in
                switch result {
                case .success(let appSettings):

                    if (allAgentIds.isEmpty) {
                        allAgentIds.append(appSettings.agentID)
                    }
                    // If single threaded is not enabled for this conversation,
                    // then check in global app settings.
                    if !conversation.useLastConversation,
                       let chatWidget = appSettings.chatWidget,
                       let isSingleThreaded = chatWidget.isSingleThreaded {
                        conversation.useLastConversation = isSingleThreaded
                    }
                case .failure(let error):
                    completion(.failure(KMConversationError.api(error)))
                    return
                }
                allAgentIds = allAgentIds.uniqueElements
                conversation.agentIds = allAgentIds
                conversation.botIds = allBotIds

                let isClientIdEmpty = (conversation.clientConversationId ?? "").isEmpty
                if isClientIdEmpty && conversation.useLastConversation {
                    conversation.clientConversationId = service.createClientIdFrom(
                        userId: conversation.userId,
                        agentIds: conversation.agentIds,
                        botIds: conversation.botIds ?? [])
                }
                service.createConversation(conversation: conversation, completion: { response in
                    DispatchQueue.main.async {
                        guard let conversationId = response.clientChannelKey else {
                            completion(.failure(KMConversationError.api(response.error)))
                            return;
                        }
                        KMCustomEventHandler.shared.publish(triggeredEvent: CustomEvent.newConversation, data: ["UserSelection":["ClientConversationId":conversation.clientConversationId]])
                        completion(.success(conversationId))
                    }
                })
            }
        } else {
            completion(.failure(KMConversationError.notLoggedIn))
        }
    }

    /// This method is used to return an instance of conversation list view controller.
    ///
    /// - Returns: Instance of `ALKConversationListViewController`
    @objc open class func conversationListViewController() -> KMConversationListViewController {
        let conversationVC = KMConversationListViewController(configuration: Kommunicate.defaultConfiguration, kmConversationViewConfiguration: Kommunicate.kmConversationViewConfiguration)
        configureListVC(conversationVC)
        return conversationVC
    }

    /**
     Launch chat list from a ViewController.

     - Parameters:
     - viewController: ViewController from which the chat list will be launched.
     */
    @objc open class func showConversations(from viewController: UIViewController) {
        let conversationVC = conversationListViewController()
        let navVC = KMBaseNavigationViewController(rootViewController: conversationVC)
        navVC.modalPresentationStyle = .fullScreen
        viewController.present(navVC, animated: true, completion: nil)
    }

    /**
     Launch group chat from a ViewController

     - Parameters:
     - clientGroupId: clientChannelKey of the Group.
     - viewController: ViewController from which the group chat will be launched.
     - prefilledMessage: Prefilled message for chatbox.
     - showListOnBack: If true, then the conversation list will be shown on tap of the back button,
     - completionHandler: Called with the information whether the conversation was
     shown or not.

     */
    @objc open class func showConversationWith(
        groupId clientGroupId: String,
        from viewController: UIViewController,
        prefilledMessage: String? = nil,
        showListOnBack: Bool = false,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alChannelService = ALChannelService()
        alChannelService.getChannelInformation(nil, orClientChannelKey: clientGroupId) { (channel) in
            guard let channel = channel, let key = channel.key else {
                completionHandler(false)
                return
            }
            self.openChatWith(
                groupId: key,
                from: viewController,
                prefilledMessage: prefilledMessage,
                showListOnBack: showListOnBack) { result in
                completionHandler(result)
            }
        }
    }

    /**
     Creates and launches the conversation. In case multiple conversations
     are present then the conversation list will be presented. If a single
     conversation is present then that will be launched.

     - Parameters:
     - viewController: ViewController from which the group chat will be launched.
     */

    open class func createAndShowConversation(
        from viewController: UIViewController,
        completion:@escaping (_ error: KommunicateError?) -> ()){
        guard isLoggedIn else {
            completion(KommunicateError.notLoggedIn)
            return
        }

        let applozicClient = applozicClientType.init(applicationKey: KMUserDefaultHandler.getApplicationKey())
        applozicClient?.getLatestMessages(false, withCompletionHandler: {
            messageList, error in
            print("Kommunicate: message list received")

            // If more than 1 thread is present then the list will be shown
            if let messages = messageList, messages.count > 1, error == nil {
                showConversations(from: viewController)
                completion(nil)
            } else {
                createAConversationAndLaunch(from: viewController, completion: {
                    conversationError in
                    completion(conversationError)
                })
            }
        })
    }
    
    /**
     Updates the conversation parameters.
     Requires the conversation ID and the specific parameters that need to be updated for the specified conversation ID.

     - Parameters:
     - conversation: Conversation that needs to be updated
     - completion: Called with the status of the conversation update
     */
    open class func updateConversation(conversation: KMConversation, completion:@escaping (Result<String, KommunicateError>) -> ()) {
        
        let service = KMConversationService()
        guard let groupID = conversation.clientConversationId, !groupID.isEmpty else { return }
        if let teamID = conversation.teamId, !teamID.isEmpty {
            service.updateTeam(groupID: groupID, teamID: teamID) { response in
                if (response.success) {
                    completion(.success(groupID))
                } else {
                    completion(.failure(KommunicateError.conversationUpdateFailed))
                }
            }
        } else { completion(.failure(KommunicateError.teamNotPresent)) }
    }

    /**
     Generates a random id that can be used as an `userId`
     when you don't have any user information that can be used as an
     userId.

     - Returns: A random alphanumeric string of length 32.
     */
    @objc open class func randomId() -> String {
        return String.random(length: 32)
    }

    open class func openFaq(from vc: UIViewController, with configuration: ALKConfiguration) {
        guard let url = URLBuilder.faqURL(for: ALUserDefaultsHandler.getApplicationKey()).url else {
            return
        }
        let faqVC = FaqViewController(url: url, configuration: configuration)
        let navVC = KMBaseNavigationViewController(rootViewController: faqVC)
        vc.present(navVC, animated: true, completion: nil)
    }

    /// Sends a new message from the logged-in user.
    /// - Parameter message: An instance of `KMMessage` object.
    /// - Parameter completion: If there's any error while sending this message, then it will be returned in this block.
    open class func sendMessage(
        message: KMMessage,
        completion: @escaping (Error?) -> ()) {
        guard !message.conversationId.isEmpty else {
            let emptyConversationId = NSError(domain:"Empty conversation ID", code:0, userInfo:nil)
            completion(emptyConversationId)
            return
        }
        let alChannelService = ALChannelService()
        alChannelService.getChannelInformation(nil, orClientChannelKey: message.conversationId) { channel in
            guard let channel = channel, let key = channel.key else {
                let noConversationError = NSError(domain:"No conversation found", code:0, userInfo:nil)
                completion(noConversationError)
                return
            }
            let alMessage = message.toALMessage()
            alMessage.groupId = key
            ALMessageService.sharedInstance().sendMessages(alMessage) { _, error in
                guard error == nil else {
                    completion(error)
                    return
                }
                completion(nil)
            }
        }
    }
    
    /**
     Creates and launches the conversation with PreChat Lead Collection.

     - Parameters:
     - appID: User's application ID.
     - conversation: Instance of a KMConversation object, can be set to nil or customized as required.
     - viewController: ViewController from which the pre-chat form view will be launched.
     */

    open class func createConversationWithPreChat(appID: String, conversation: KMConversation?, viewController: UIViewController, completion: @escaping(KommunicateError?) -> ()) {
        
        KMUserDefaultHandler.setApplicationKey(appID)
        Kommunicate.presentingViewController = viewController
    
        let kmAppSetting = KMAppSettingService()
        kmAppSetting.appSetting { (result) in
            switch result {
            case .success(let appSetting):
                guard let isPreChatEnable = appSetting.collectLead else { return }
                if isPreChatEnable {
                    UserDefaults.standard.set(appSetting.chatWidget?.preChatGreetingMsg!, forKey: "leadCollectionTitle")
                    leadArray = appSetting.leadCollection!
                    if !KMUserDefaultHandler.isLoggedIn() {
                        DispatchQueue.main.async {
                            if !Kommunicate.leadArray.isEmpty {
                                let customPreChatVC = CustomPreChatFormViewController(configuration: Kommunicate.defaultConfiguration)
                                customPreChatVC.submitButtonTapped = {
                                    Kommunicate().userSubmittedResponse(name: customPreChatVC.formView.name, email: customPreChatVC.formView.email, phoneNumber: customPreChatVC.formView.phoneNumber, password: "")
                                }
                                customPreChatVC.closeButtonTapped = {
                                    Kommunicate().closeButtonTapped()
                                }
                                viewController.present(customPreChatVC, animated: false, completion: nil)
                            } else {
                                let preChatVC = KMPreChatFormViewController(configuration: Kommunicate.defaultConfiguration)
                                preChatVC.submitButtonTapped = {
                                    Kommunicate().userSubmittedResponse(name: preChatVC.formView.nameTextField.text!, email: preChatVC.formView.emailTextField.text!, phoneNumber: preChatVC.formView.phoneNumberTextField.text!, password: "")
                                }
                                preChatVC.closeButtonTapped = {
                                    Kommunicate().closeButtonTapped()
                                }
                                viewController.present(preChatVC, animated: false, completion: nil)
                            }
                        }
                    }
                    completion(nil)
                } else {
                    print("Pre-Chat Lead Collection is not enabled.")
                    
                    let applozicClient = applozicClientType.init(applicationKey: appID)
                    let kmUser = KMUser()
                    kmUser.userId = Kommunicate.randomId()
                    kmUser.applicationId = applicationId
                    
                    Kommunicate.registerUser(kmUser, completion: {
                        response, error in
                        guard error == nil else {
                            print("[REGISTRATION] Kommunicate user registration error: %@", error.debugDescription)
                            return
                        }
                        print("User registration was successful: %@ \(String(describing: response?.isRegisteredSuccessfully()))")
                        
                        if conversation != nil {
                            createConversation(conversation: conversation!) { (result) in
                                switch result {
                                case .success(let conversationId):
                                    DispatchQueue.main.async {
                                        showConversationWith(groupId: conversationId, from: viewController, completionHandler: { success in
                                            guard success else {
                                                completion(KommunicateError.conversationNotPresent)
                                                return
                                            }
                                            print("Kommunicate: conversation was shown")
                                            completion(nil)
                                        })
                                    }
                                case .failure(_):
                                    completion(KommunicateError.conversationCreateFailed)
                                    return
                                }
                            }
                        } else {
                            Kommunicate.createAndShowConversation(from: viewController, completion: {
                                error in
                                if error != nil {
                                    print("Error while launching")
                                }
                            })
                            let kommunicateConversationBuilder = KMConversationBuilder()
                                .useLastConversation(false)
                            let conversation = kommunicateConversationBuilder.build()
                            createConversation(conversation: conversation) { (result) in
                                switch result {
                                case .success(let conversationId):
                                    DispatchQueue.main.async {
                                        showConversationWith(groupId: conversationId, from: viewController, completionHandler: { success in
                                            guard success else {
                                                completion(KommunicateError.conversationNotPresent)
                                                return
                                            }
                                            print("Kommunicate: conversation was shown")
                                            completion(nil)
                                        })
                                    }
                                case .failure(_):
                                    completion(KommunicateError.conversationCreateFailed)
                                    return
                                }
                            }
                        }
                    })
                }
            case .failure(let error) :
                print("Error in fetching Kommunicate app settings: %@", error)
                completion(KommunicateError.appSettingsFetchFailed)
            }
        }
    }
    
    public func userSubmittedResponse(name: String, email: String, phoneNumber: String, password: String) {
        
        guard let appID = KMUserDefaultHandler.getApplicationKey() else { return }
        Kommunicate.presentingViewController.dismiss(animated: false, completion: nil)
        let kmUser = KMUser.init()
        kmUser.applicationId = appID
        if !email.isEmpty {
            kmUser.userId = email
            kmUser.email = email
        } else {
            kmUser.userId = name
        }
        if !phoneNumber.isEmpty {
            kmUser.contactNumber = phoneNumber
        }
        kmUser.contactNumber = phoneNumber
        kmUser.displayName = name
        
        Kommunicate.setup(applicationId: appID)
        Kommunicate.registerUser(kmUser, completion: {
            response, error in
            guard error == nil else {
                print("[REGISTRATION] Kommunicate user registration error: %@", error.debugDescription)
                return
            }
            print("User registration was successful: %@ \(String(describing: response?.isRegisteredSuccessfully()))")
            Kommunicate.createAndShowConversation(from: Kommunicate.presentingViewController, completion: {
                error in
                if error != nil {
                    print("Error while launching conversation")
                }
            })
        })
    }
    
    public func closeButtonTapped() {
        Kommunicate.presentingViewController.dismiss(animated: true, completion: nil)
    }

    //MARK: - Internal methods

    class func configureListVC(_ vc: KMConversationListViewController) {
        vc.conversationListTableViewController.dataSource.cellConfigurator = {
            (messageModel, tableCell) in
            let cell = tableCell as! ALKChatCell
            let message = ChatMessage(message: messageModel)
            cell.update(viewModel: message, identity: nil)
            cell.delegate = vc.conversationListTableViewController.self
        }
        let conversationViewController = KMConversationViewController(configuration: Kommunicate.defaultConfiguration, conversationViewConfiguration: kmConversationViewConfiguration, individualLaunch: false)
        conversationViewController.viewModel = ALKConversationViewModel(contactId: nil, channelKey: nil, localizedStringFileName: defaultConfiguration.localizedStringFileName)
        vc.conversationViewController = conversationViewController
    }

    class func openChatWith(
        groupId: NSNumber,
        from viewController: UIViewController,
        prefilledMessage: String? = nil,
        showListOnBack: Bool = false,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if showListOnBack {
            let conversationListVC = conversationListViewController()
            conversationListVC.channelKey = groupId
            let navVC = KMBaseNavigationViewController(rootViewController: conversationListVC)
            navVC.modalPresentationStyle = .fullScreen
            viewController.present(navVC, animated: true) {
                completionHandler(true)
            }
        } else {
            let convViewModel = ALKConversationViewModel(contactId: nil, channelKey: groupId, localizedStringFileName: defaultConfiguration.localizedStringFileName, prefilledMessage: prefilledMessage)
            let conversationVC = KMConversationViewController(configuration: Kommunicate.defaultConfiguration, conversationViewConfiguration: kmConversationViewConfiguration)
            conversationVC.viewModel = convViewModel
            let navVC = KMBaseNavigationViewController(rootViewController: conversationVC)
            navVC.modalPresentationStyle = .fullScreen
            viewController.present(navVC, animated: true) {
                completionHandler(true)
            }
        }
    }

    //MARK: - Private methods

    private func updateToken() {
        guard let deviceToken = pushNotificationTokenData else { return }
        print("DEVICE_TOKEN_DATA :: \(deviceToken.description)")  // (SWIFT = 3) : TOKEN PARSING

        var deviceTokenString: String = ""
        for i in 0..<deviceToken.count
        {
            deviceTokenString += String(format: "%02.2hhx", deviceToken[i] as CVarArg)
        }
        print("DEVICE_TOKEN_STRING :: \(deviceTokenString)")

        if (ALUserDefaultsHandler.getApnDeviceToken() != deviceTokenString)
        {
            let alRegisterUserClientService: ALRegisterUserClientService = ALRegisterUserClientService()
            alRegisterUserClientService.updateApnDeviceToken(withCompletion: deviceTokenString, withCompletion: { (response, error) in
                print ("REGISTRATION_RESPONSE :: \(String(describing: response))")
            })
        }
    }

    private class func createAConversationAndLaunch(
        from viewController: UIViewController,
        completion:@escaping (_ error: KommunicateError?) -> ()) {
        let kommunicateConversationBuilder = KMConversationBuilder()
            .useLastConversation(true)
        let conversation = kommunicateConversationBuilder.build()
        createConversation(conversation: conversation) { (result) in
            switch result {
            case .success(let conversationId):
                DispatchQueue.main.async {
                    showConversationWith(groupId: conversationId, from: viewController, completionHandler: { success in
                        guard success else {
                            completion(KommunicateError.conversationNotPresent)
                            return
                        }
                        print("Kommunicate: conversation was shown")
                        completion(nil)
                    })
                }
            case .failure(_):
                completion(KommunicateError.conversationCreateFailed)
                return
            }
        }
    }

    func defaultChatViewSettings() {
        KMUserDefaultHandler.setBASEURL(API.Backend.chat.rawValue)
        KMUserDefaultHandler.setGoogleMapAPIKey("AIzaSyCOacEeJi-ZWLLrOtYyj3PKMTOFEG7HDlw") //REPLACE WITH YOUR GOOGLE MAPKEY
        ALApplozicSettings.setListOfViewControllers([ALKConversationListViewController.description(), KMConversationViewController.description()])
        ALApplozicSettings.setFilterContactsStatus(true)
        ALUserDefaultsHandler.setDebugLogsRequire(true)
        ALApplozicSettings.setSwiftFramework(true)
        ALApplozicSettings.hideMessages(withMetadataKeys: ["KM_ASSIGN", "KM_STATUS"])
    }

    func setupDefaultStyle() {
        let navigationBarProxy = UINavigationBar.appearance(whenContainedInInstancesOf: [ALKBaseNavigationViewController.self])
        navigationBarProxy.tintColor = navigationBarProxy.tintColor ?? UIColor.white
        navigationBarProxy.titleTextAttributes =
            navigationBarProxy.titleTextAttributes ?? [NSAttributedString.Key.foregroundColor: UIColor.white]
        KMMessageStyle.sentMessage = KMStyle(font: KMMessageStyle.sentMessage.font, text: UIColor.white)
    }

    /**
     Creates a new conversation with the details passed.

     - Parameters:
     - userId: User id of the participant.
     - agentId: User id of the agent.
     - botIds: A list of bot ids to be added in the conversation.
     - useLastConversation: If there is a conversation already present then that will be returned.

     - Returns: Group id if successful otherwise nil.
     */
    @available(*, deprecated, message: "Use createConversation(conversation:completion:)")
    @objc open class func createConversation(
        userId: String,
        agentIds: [String] = [],
        botIds: [String]?,
        useLastConversation: Bool = false,
        clientConversationId: String? = nil,
        completion:@escaping (_ clientGroupId: String) -> ()) {
        let kommunicateConversationBuilder = KMConversationBuilder()
            .useLastConversation(useLastConversation)
            .withAgentIds(agentIds)
            .withBotIds(botIds ?? [])
        let conversation =  kommunicateConversationBuilder.build()

        createConversation(conversation: conversation) { (result) in

            switch result {
            case .success(let conversationId):
                completion(conversationId)
            case .failure(_):
                completion("")
            }
        }
    }

    /// Logs out the current logged in user and clears all the cache.
    @available(*, deprecated, message: "Use logoutUser(completion:)")
    @objc open class func logoutUser() {
        let registerUserClientService = ALRegisterUserClientService()
        if let _ = ALUserDefaultsHandler.getDeviceKeyString() {
            registerUserClientService.logout(completionHandler: {
                _, _ in
                Kommunicate.shared.clearUserDefaults()
                NSLog("Applozic logout")
            })
        }
    }

    private func clearUserDefaults() {
        let kmAppSetting = KMAppSettingService()
        KMAppUserDefaultHandler.shared.clear()
        kmAppSetting.clearAppSettingsData()
    }

    private static func validateUserData(user: KMUser) -> NSError? {
        guard let userId = user.userId, !userId.isEmpty else {
            return NSError(domain:"User ID is not present", code:0, userInfo:nil)
        }
        guard !userId.containsWhitespace else {
            return NSError(domain:"User ID contains whitespace or newline characters", code:0, userInfo:nil)
        }
        return nil
    }
    /**
     Subscribe Chat Events
     - Parameters:
     - events: list of events to subscribe.
     - callback: ALKCustomEventCallback to send subscribed event's data
     */
    public static func subscribeCustomEvents(events: [CustomEvent],callback: ALKCustomEventCallback){
        KMCustomEventHandler.shared.setSubscribedEvents(eventsList: events,eventDelegate: callback)
    }
}
