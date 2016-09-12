
//
//  MainController.swift
//  Kiwix
//
//  Created by Chris Li on 1/22/16.
//  Copyright © 2016 Chris. All rights reserved.
//

import UIKit
import Operations
import SafariServices

class MainController: UIViewController {
    
    // MARK: - IBOutlet
    
    @IBOutlet weak var webView: UIWebView!
    @IBOutlet weak var dimView: UIView!
    @IBOutlet weak var tocVisiualEffectView: UIVisualEffectView!
    @IBOutlet weak var tocTopToSuperViewBottomSpacing: NSLayoutConstraint!
    @IBOutlet weak var tocHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var tocLeadSpacing: NSLayoutConstraint!
    
    // MARK: - Properties
    
    let activityType = "org.kiwix.kiwix.article-view"
    private var webViewInitialURL: NSURL?
    private(set) var context: UnsafeMutablePointer<Void> = nil
    var isShowingTableOfContents = false
    private(set) var tableOfContentsController: TableOfContentsController?
    let searchBar = SearchBar()

    var article: Article? {
        willSet(newArticle) {
            article?.removeObserver(self, forKeyPath: "isBookmarked")
            newArticle?.addObserver(self, forKeyPath: "isBookmarked", options: .New, context: context)
        }
        didSet {
            configureSearchBarPlaceHolder()
            configureBookmarkButton()
            configureUserActivity()
        }
    }
    
    // MARK: - Override
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView.delegate = self
        
        
        
        navigationItem.titleView = searchBar
        searchBar.delegate = self
        ZimMultiReader.shared.delegate = self
        
        NSUserDefaults.standardUserDefaults().addObserver(self, forKeyPath: "webViewNotInjectJavascriptToAdjustPageLayout", options: .New, context: context)
        NSUserDefaults.standardUserDefaults().addObserver(self, forKeyPath: "webViewZoomScale", options: .New, context: context)
        configureButtonColor()
        showGetStartedAlert()
        showWelcome()
        load(webViewInitialURL)
    }
    
    deinit {
        NSUserDefaults.standardUserDefaults().removeObserver(self, forKeyPath: "webViewNotInjectJavascriptToAdjustPageLayout")
        NSUserDefaults.standardUserDefaults().removeObserver(self, forKeyPath: "webViewZoomScale")
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard context == self.context, let keyPath = keyPath else {return}
        switch keyPath {
        case "webViewZoomScale", "webViewNotInjectJavascriptToAdjustPageLayout":
            webView.reload()
        case "isBookmarked":
            configureBookmarkButton()
        default:
            return
        }
    }
    
    override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            configureUIElements(traitCollection.horizontalSizeClass)
        }
        configureTOCViewConstraints()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "EmbeddedTOCController" {
            guard let destinationViewController = segue.destinationViewController as? TableOfContentsController else {return}
            tableOfContentsController = destinationViewController
            tableOfContentsController?.delegate = self
        }
    }
    
    override func updateUserActivityState(activity: NSUserActivity) {
        defer { super.updateUserActivityState(activity) }
        guard let article = article else {return}
        activity.title = article.title
        activity.addUserInfoEntriesFromDictionary(["ArticleURL": article.url])
        super.updateUserActivityState(activity)
    }
    
    override func restoreUserActivityState(activity: NSUserActivity) {
        guard activity.activityType == activityType,
            let urlString = activity.userInfo?["ArticleURL"] as? String,
            let url = NSURL(string: urlString),
            let host = url.host else {return}
        if ZimMultiReader.shared.readers.keys.contains(host) {
            load(url)
        } else {
            // TODO: - Alert cannot complete hand off
        }
    }
    
    // MARK: - Load
    
    func load(url: NSURL?) {
        if webView == nil {
            webViewInitialURL = url
            return
        }
        guard let url = url else {return}
        webView.hidden = false
        hideWelcome()
        let request = NSURLRequest(URL: url)
        webView.loadRequest(request)
    }
    
    func loadMainPage(id: ZimID) {
        guard let reader = ZimMultiReader.shared.readers[id] else {return}
        let mainPageURLString = reader.mainPageURL()
        let mainPageURL = NSURL.kiwixURLWithZimFileid(id, contentURLString: mainPageURLString)
        load(mainPageURL)
    }
    
    func loadExternalResource(url: NSURL) {
        let controller = SFSafariViewController(URL: url)
        controller.delegate = self
        presentViewController(controller, animated: true, completion: nil)
    }
    
    // MARK: - Tasks
    
    func setTableOfContentIfNeeded() {
        guard traitCollection.horizontalSizeClass == .Regular && isShowingTableOfContents else {return}
        tableOfContentsController?.headings = JSInjection.getTableOfContents(webView)
    }
    
    // MARK: - Configure
    
    func configureUIElements(horizontalSizeClass: UIUserInterfaceSizeClass) {
        switch horizontalSizeClass {
        case .Regular:
            navigationController?.toolbarHidden = true
            toolbarItems?.removeAll()
            navigationItem.leftBarButtonItems = [navigateLeftButton, navigateRightButton, tableOfContentButton]
            navigationItem.rightBarButtonItems = [settingButton, libraryButton, bookmarkButton]
            searchBar.setShowsCancelButton(false, animated: true)
        case .Compact:
            if !searchBar.isFirstResponder() {navigationController?.toolbarHidden = false}
            if searchBar.isFirstResponder() {searchBar.setShowsCancelButton(true, animated: true)}
            navigationItem.leftBarButtonItems?.removeAll()
            navigationItem.rightBarButtonItems?.removeAll()
            let spaceButton = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
            toolbarItems = [navigateLeftButton, spaceButton, navigateRightButton, spaceButton, tableOfContentButton, spaceButton, bookmarkButton, spaceButton, libraryButton, spaceButton, settingButton]            
            if UIDevice.currentDevice().userInterfaceIdiom == .Pad && searchBar.isFirstResponder() {
                navigationItem.setRightBarButtonItem(cancelButton, animated: true)
            }
        case .Unspecified:
            break
        }
    }
    
    func configureButtonColor() {
        configureNavigationButtonTint()
        tableOfContentButton.tintColor = UIColor.grayColor()
        libraryButton.tintColor = UIColor.grayColor()
        settingButton.tintColor = UIColor.grayColor()
        UIBarButtonItem.appearanceWhenContainedInInstancesOfClasses([UISearchBar.self]).tintColor = UIColor.themeColor
    }
    
    func configureNavigationButtonTint() {
        navigateLeftButton.tintColor = webView.canGoBack ? nil : UIColor.grayColor()
        navigateRightButton.tintColor = webView.canGoForward ? nil : UIColor.grayColor()
    }
    
    func configureBookmarkButton() {
        bookmarkButton.customImageView?.highlighted = article?.isBookmarked ?? false
    }
    
    func configureWebViewInsets() {
        let topInset: CGFloat = {
            guard let navigationBar = navigationController?.navigationBar else {return 44.0}
            return navigationBar.hidden ? 0.0 : navigationBar.frame.origin.y + navigationBar.frame.height
        }()
        let bottomInset: CGFloat = {
            guard let toolbar = navigationController?.toolbar else {return 0.0}
            return traitCollection.horizontalSizeClass == .Compact ? view.frame.height - toolbar.frame.origin.y : 0.0
        }()
        webView.scrollView.contentInset = UIEdgeInsetsMake(topInset, 0, bottomInset, 0)
        webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(topInset, 0, bottomInset, 0)
    }
    
    func configureSearchBarPlaceHolder() {
        func truncatedPlaceHolderString(string: String?, searchBar: UISearchBar) -> String? {
            guard let string = string else {return nil}
            guard let label = searchBar.valueForKey("_searchField") as? UITextField else {return nil}
            guard let labelFont = label.font else {return nil}
            let preferredSize = CGSizeMake(searchBar.frame.width - 45.0, 1000)
            var rect = (string as NSString).boundingRectWithSize(preferredSize, options: NSStringDrawingOptions.UsesLineFragmentOrigin, attributes: [NSFontAttributeName: labelFont], context: nil)
            
            var truncatedString = string as NSString
            var istruncated = false
            while rect.height > label.frame.height {
                istruncated = true
                truncatedString = truncatedString.substringToIndex(truncatedString.length - 2)
                rect = truncatedString.boundingRectWithSize(preferredSize, options: NSStringDrawingOptions.UsesLineFragmentOrigin, attributes: [NSFontAttributeName: labelFont], context: nil)
            }
            return truncatedString as String + (istruncated ? "..." : "")
        }
        
        if let title = article?.title {
            let placeHolder =  truncatedPlaceHolderString(title, searchBar: searchBar)
            searchBar.placeholder = placeHolder
        } else {
            searchBar.placeholder = LocalizedStrings.search
        }
    }
    
    func configureUserActivity() {
        userActivity = userActivity ?? NSUserActivity(activityType: activityType)
        guard let article = article else {return}
        userActivity?.title = article.title
        userActivity?.userInfo = ["ArticleURL": article.url]
        userActivity?.eligibleForHandoff = true
        userActivity?.supportsContinuationStreams = true
        userActivity?.becomeCurrent()
    }

    // MARK: - Buttons

    lazy var navigateLeftButton: UIBarButtonItem = UIBarButtonItem(imageNamed: "LeftArrow", target: self, action: #selector(MainController.navigateLeftButtonTapped))
    lazy var navigateRightButton: UIBarButtonItem = UIBarButtonItem(imageNamed: "RightArrow", target: self, action: #selector(MainController.navigateRightButtonTapped))
    lazy var tableOfContentButton: UIBarButtonItem = UIBarButtonItem(imageNamed: "TableOfContent", target: self, action: #selector(MainController.showTableOfContentButtonTapped))
    lazy var bookmarkButton: LPTBarButtonItem = LPTBarButtonItem(imageName: "Star", highlightedImageName: "StarHighlighted", delegate: self)
    lazy var libraryButton: UIBarButtonItem = UIBarButtonItem(imageNamed: "Library", target: self, action: #selector(MainController.showLibraryButtonTapped))
    lazy var settingButton: UIBarButtonItem = UIBarButtonItem(imageNamed: "Setting", target: self, action: #selector(MainController.showSettingButtonTapped))
    lazy var cancelButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Cancel, target: self, action: #selector(MainController.cancelButtonTapped))
    
    // MARK: - Actions
    
    func navigateLeftButtonTapped() {
        webView.goBack()
    }
    
    func navigateRightButtonTapped() {
        webView.goForward()
    }
    
    func showTableOfContentButtonTapped(sender: UIBarButtonItem) {
        guard let _ = article else {return}
        isShowingTableOfContents ? animateOutTableOfContentsController() :animateInTableOfContentsController()
    }
    
    func showLibraryButtonTapped() {
        let controller = ControllerRetainer.library
        controller.modalPresentationStyle = .FullScreen
        presentViewController(controller, animated: true, completion: nil)
    }
    
    func showSettingButtonTapped() {
        let controller = ControllerRetainer.setting
        controller.modalPresentationStyle = .FormSheet
        presentViewController(controller, animated: true, completion: nil)
    }
    
    func cancelButtonTapped() {
        hideSearch(animated: true)
        navigationItem.setRightBarButtonItem(nil, animated: true)
    }
    
    @IBAction func dimViewTapGestureRecognizer(sender: UITapGestureRecognizer) {
        animateOutTableOfContentsController()
    }
}
