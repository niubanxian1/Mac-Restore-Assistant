import SwiftUI
import AppKit

/// Personal contact and About-page resources. These values must stay on the
/// About page only; do not import this type into capture logs or ZIP export.
enum AboutSoftwareInfo {
    static let authorName = "刘海峰"
    static let displayNameChinese = "牛半仙 Mac 维修辅助工具"
    static let displayNameEnglish = "Mac Restore Assistant"
    static let developerDisplay = "牛半仙（niubanxian1）"
    static let githubURL = URL(string: "https://github.com/niubanxian1/Mac-Restore-Assistant")!
    static let licenseURL = URL(string: "https://github.com/niubanxian1/Mac-Restore-Assistant/blob/main/LICENSE")!
    static let email = "liuhaifeng2001522@gmail.com"
    static let iconResourceName = "小牛图标"
    static let wechatResourceName = "微信"
    static let wechatResourceExtension = "JPG"
    /// Original pixel size of the desktop WeChat card; keep this aspect ratio.
    static let wechatPixelSize = CGSize(width: 888, height: 1131)
    /// Default on-page width that stays easy to scan without cropping margins.
    static let wechatDefaultDisplayWidth: CGFloat = 240

    static var appName: String {
        let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        let value = (display?.isEmpty == false ? display : name) ?? "牛半仙Mac维修辅助工具"
        return value
    }

    static var shortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    static var buildVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    }

    static var versionDisplay: String {
        let short = shortVersion.isEmpty ? "—" : shortVersion
        let build = buildVersion.isEmpty ? "—" : buildVersion
        let prefix: String
        switch L10n.code() {
        case "en": prefix = "Version "
        case "zh-Hant": prefix = "版本 "
        case "ja": prefix = "バージョン "
        case "ko": prefix = "버전 "
        default: prefix = "版本 "
        }
        return "\(prefix)\(short) (\(build))"
    }

    static func wechatImageURL() -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: wechatResourceName, withExtension: wechatResourceExtension) {
            return url
        }
        if let url = bundle.url(forResource: wechatResourceName, withExtension: wechatResourceExtension.lowercased()) {
            return url
        }
        let fallback = bundle.resourceURL?.appendingPathComponent("\(wechatResourceName).\(wechatResourceExtension)")
        if let fallback, FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    static func wechatImage() -> NSImage? {
        guard let url = wechatImageURL() else { return nil }
        return NSImage(contentsOf: url)
    }

    static func appIconImage() -> NSImage {
        if let icon = NSApp.applicationIconImage, icon.size.width > 16 {
            return icon
        }
        if let url = Bundle.main.url(forResource: iconResourceName, withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage ?? NSImage()
    }

    static func copyEmailToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(email, forType: .string)
    }
}

struct AboutSoftwareView: View {
    @EnvironmentObject private var language: LanguageStore
    @State private var showEnlargedQR = false
    @State private var copyMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: AboutSoftwareInfo.appIconImage())
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.appDisplayName)
                            .font(.system(size: 18, weight: .semibold))
                        if language.resolvedCode == "zh-Hans" || language.resolvedCode == "zh-Hant" {
                            Text(AboutSoftwareInfo.displayNameEnglish)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Text(AboutSoftwareInfo.versionDisplay)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("作者"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(AboutSoftwareInfo.authorName)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                    Text(L10n.t("开发者"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(AboutSoftwareInfo.developerDisplay)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                    HStack(alignment: .center, spacing: 10) {
                        Text(AboutSoftwareInfo.email)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                        Button(L10n.t("复制邮箱")) {
                            AboutSoftwareInfo.copyEmailToPasteboard()
                            copyMessage = "已复制 \(AboutSoftwareInfo.email)"
                        }
                        .buttonStyle(.bordered)
                    }
                    if !copyMessage.isEmpty {
                        Text(copyMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("关于这个项目"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(L10n.t("我是一名 MacBook 维修工程师。最初开发这个工具，只是想让日常 DFU、Revive 和 Restore 操作变得更方便、更稳定。\n\n现在，我希望把它免费分享给更多同行。"))
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text(L10n.t("我的开源理念"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(L10n.t("我希望这个工具不仅仅属于我一个人，而是能够通过大家的使用、研究和改进，逐渐变得更加完善。\n\n你可以自由使用、研究、修改和分发它，也欢迎在此基础上开发更强大的功能。\n\n如果你修复了问题，或者做出了更好的功能，我非常希望你能将这些改进分享回来，让更多人受益。\n\n分享不是义务，进步才是初衷。"))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Link(destination: AboutSoftwareInfo.githubURL) {
                        Text(L10n.t("GitHub：\(AboutSoftwareInfo.githubURL.absoluteString)"))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .accessibilityIdentifier("about.github")
                    HStack(spacing: 4) {
                        Text(L10n.t("许可证："))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Link("MIT License", destination: AboutSoftwareInfo.licenseURL)
                            .font(.system(size: 12))
                    }
                    Text(L10n.t("© 2026 niubanxian1"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("微信"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(L10n.t("用手机扫描下方原图即可添加。点击图片可放大查看。"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    wechatButton
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showEnlargedQR) {
            enlargedQR
        }
    }

    @ViewBuilder
    private var wechatButton: some View {
        if let image = AboutSoftwareInfo.wechatImage() {
            Button {
                showEnlargedQR = true
            } label: {
                wechatCard(image: image, width: AboutSoftwareInfo.wechatDefaultDisplayWidth)
            }
            .buttonStyle(.plain)
            .help("点击放大原图")
        } else {
            Text(L10n.t("未找到随 App 打包的微信名片原图。"))
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    private func wechatCard(image: NSImage, width: CGFloat) -> some View {
        let aspect = AboutSoftwareInfo.wechatPixelSize.width / AboutSoftwareInfo.wechatPixelSize.height
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .aspectRatio(aspect, contentMode: .fit)
            .frame(width: width)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
    }

    private var enlargedQR: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.t("微信名片原图"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(L10n.t("关闭")) { showEnlargedQR = false }
                    .keyboardShortcut(.cancelAction)
            }
            if let image = AboutSoftwareInfo.wechatImage() {
                ScrollView([.horizontal, .vertical]) {
                    wechatCard(image: image, width: 480)
                        .padding(8)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
