import ProjectDescription

let bundleID = "com.example.databasekit.bookmarks"
let appGroup = "group.com.example.databasekit.bookmarks"

let appleDestinations: Destinations = [.iPhone, .iPad, .mac, .appleTv]
let deployment: DeploymentTargets = .multiplatform(iOS: "18.0", macOS: "15.0", tvOS: "18.0")

/// The App Groups entitlement is what lets the app and its extensions open the same `.group` store.
/// The sandbox key is required on macOS for a Safari extension and ignored elsewhere.
let sharedEntitlements: Entitlements = .dictionary([
    "com.apple.security.application-groups": .array([.string(appGroup)]),
    "com.apple.security.app-sandbox": .boolean(true),
])

let settings: Settings = .settings(base: [
    "SWIFT_VERSION": "6.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "APP_GROUP_IDENTIFIER": .string(appGroup),
])

let project = Project(
    name: "Bookmarks",
    packages: [.local(path: "..")],
    settings: settings,
    targets: [
        .target(
            name: "BookmarksKit",
            destinations: appleDestinations,
            product: .framework,
            bundleId: "\(bundleID).kit",
            deploymentTargets: deployment,
            sources: ["Sources/BookmarksKit/**"],
            dependencies: [.package(product: "DatabaseKit")]
        ),
        .target(
            name: "Bookmarks",
            destinations: appleDestinations,
            product: .app,
            bundleId: bundleID,
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
                "CFBundleDisplayName": "Bookmarks",
            ]),
            sources: ["Sources/App/**"],
            entitlements: sharedEntitlements,
            dependencies: [
                .target(name: "BookmarksKit"),
                .target(name: "BookmarksShareExtension", condition: .when([.ios])),
                .target(name: "BookmarksSafariExtension", condition: .when([.ios, .macos])),
            ]
        ),
        .target(
            name: "BookmarksShareExtension",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "\(bundleID).share",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Save to Bookmarks",
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "NSExtensionAttributes": .dictionary([
                        "NSExtensionActivationRule": .dictionary([
                            "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                        ]),
                    ]),
                ]),
            ]),
            sources: ["Sources/ShareExtension/**"],
            entitlements: sharedEntitlements,
            dependencies: [.target(name: "BookmarksKit")]
        ),
        .target(
            name: "BookmarksSafariExtension",
            destinations: [.iPhone, .iPad, .mac],
            product: .appExtension,
            bundleId: "\(bundleID).safari",
            deploymentTargets: .multiplatform(iOS: "18.0", macOS: "15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Bookmarks for Safari",
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
                ]),
            ]),
            sources: ["Sources/SafariExtension/**"],
            resources: [.folderReference(path: "Resources/SafariExtension")],
            entitlements: sharedEntitlements,
            dependencies: [.target(name: "BookmarksKit")]
        ),
        .target(
            name: "BookmarksKitTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "\(bundleID).kit.tests",
            deploymentTargets: .multiplatform(iOS: "18.0", macOS: "15.0"),
            sources: ["Tests/BookmarksKitTests/**"],
            dependencies: [
                .target(name: "BookmarksKit"),
                .package(product: "DatabaseKitTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "BookmarksKit",
            buildAction: .buildAction(targets: ["BookmarksKit"]),
            testAction: .targets(["BookmarksKitTests"])
        ),
    ]
)
