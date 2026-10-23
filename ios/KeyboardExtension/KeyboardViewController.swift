import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var model = KeyboardModel(
        insert: { [weak self] text in self?.textDocumentProxy.insertText(text) },
        deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
        currentDraft: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput ?? "" },
        hasFullAccess: { [weak self] in self?.hasFullAccess ?? false }
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = KeyboardView(
            model: model,
            needsGlobe: needsInputModeSwitchKey,
            onGlobe: { [weak self] in self?.advanceToNextInputMode() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        // 顶部栏 46 + 四行按键，接近系统键盘高度；优先级低于必需，避免和系统约束冲突
        let height = host.view.heightAnchor.constraint(equalToConstant: 272)
        height.priority = .init(999)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)
    }
}
