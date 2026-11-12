# Icon Composer and sidebar verification

Checked on 25 October 2026 with Xcode 27.1 (27A9275), Icon Composer 27.1 (129), and the macOS 27.0 SDK.

## Icon source and target configuration

The existing configuration is correct; no icon or build-setting substitution was made.

| Item | iOS PortSight | macOS PortsightMac |
| --- | --- | --- |
| Source | `PortSight/PortSight.icon` | `PortsightMac/Resources/PortSight.icon` |
| Document | Package containing `icon.json` and `Assets/image3 2.png` | Identical package and file hashes |
| Xcode file type | Explicit `folder.iconcomposer.icon` file reference | Inferred from `.icon` within the target's synchronized folder |
| Target membership | Explicit `PortSight.icon in Resources` build entry | `PortsightMac` synchronized root belongs to the application target; no exclusion |
| Primary icon, Debug and Release | `ASSETCATALOG_COMPILER_APPICON_NAME = PortSight` | Same |
| Platform | iPhone/iPad | `SDKROOT = macosx`, `SUPPORTED_PLATFORMS = macosx`, deployment 27.0 |

The macOS build command passes the original `.icon` package and `Assets.xcassets` to `actool`, with `--app-icon PortSight --target-device mac --platform macosx`. It is not copied as an ordinary folder or omitted from the target.

The local SDK's `AssetCatalogCompiler.xcspec` explicitly accepts `folder.iconcomposer.icon`, maps `ASSETCATALOG_COMPILER_APPICON_NAME` to `--app-icon`, and generates the icon-related Info.plist content. Do not add competing manual `CFBundleIconFile` keys or replace the document with a flattened PNG.

Apple's [Icon Composer integration instructions](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) specify adding the `.icon` document to the target and using its filename without the extension as the App Icon name. Both projects already do this. The existing document uses `supported-platforms.squares = shared`, preserving its iOS/macOS design.

SHA-256, identical in both projects:

- `icon.json`: `8a8486272dc1f6bfc8d401c23d3a6fd4c860a6a3490f815dd190bda28166a9f9`
- `Assets/image3 2.png`: `a4c44a3de7dead3b84aa49234e440d755d23d220abef355908233b1b8c69b16b`

## Reproduced build failure

A fresh build using `/tmp/PortsightMac-icon-build` failed with:

```text
The file “PortSight.icon” couldn’t be opened.
Icon export exited with status 255, signal 0
Failed to create a catalog from the Icon Studio document
```

The bundled Icon Composer `ictool` also failed directly on the Mac source, the original iOS source, and an unchanged temporary copy. Reading `icon.json` as bytes succeeded. Foundation `FileWrapper` and URL content-type lookup failed before any icon rendering:

```text
NSCocoaErrorDomain Code=256
NSOSStatusErrorDomain Code=-10813
kLSDataUnavailableErr: E.g. no kind string
```

In this command environment, `UTType(filenameExtension: "icon")` returned a dynamic type instead of `com.apple.iconcomposer.icon`. The failure is in the system file-type lookup path, not a missing resource or mismatched icon name. The earlier Xcode-built application already contains `Assets.car` and `PortSight.icns`, with generated `CFBundleIconName` and `CFBundleIconFile` both set to `PortSight`.

A request to build outside the restricted command environment was rejected because the session's approval policy does not permit escalation. Therefore a successful fresh full build has **not** been verified. No Launch Services database, system permission, original icon design, signing setting, or application sandbox setting was changed.

## Sidebar verification status

| Check | Status |
| --- | --- |
| Seven native outline/filled SF Symbol pairs | Passed in a standalone renderer using the actual sidebar source |
| Black outline inactive state and black filled active state | Passed, all seven selected-state renders inspected |
| One opaque white selection background sliding from row 1 to row 4 and back | Passed in an `NSHostingView`; recorded frames contain intermediate positions with no disappearance |
| Full current App build and UI tests | Blocked by icon file-type lookup failure in this environment |
| Actual system tooltip for selected and inactive icons | **Not yet verified**, not classified as failed |
| Actual system tooltip after changing selection | **Not yet verified**, not classified as failed |
| New tooltip test against the installed XCTest/XCUIAutomation SDK | Type-check passed; live execution remains pending |

`PortsightMacUITests/DesktopSidebarTooltipTests.swift` now performs real XCTest `hover()` actions and waits for a visible system `helpTag`. It checks the displayed text and saves screenshots. It covers every initial navigation item, selected and deselected states after changing from Overview to Orders and back, and Settings. The test does not treat an accessibility help attribute or the presence of `.help` in source as a successful tooltip.

Run the tooltip test in Xcode's Test navigator, or from an ordinary local terminal:

```sh
xcodebuild -project PortsightMac.xcodeproj -scheme PortsightMac \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/PortsightMac-icon-validation \
  -only-testing:PortsightMacUITests/DesktopSidebarTooltipTests test
```

The tooltip test is prepared for execution; it has not passed a live run in this session. Keep the existing sidebar layout and animation while diagnosing any failure reported by that test.
