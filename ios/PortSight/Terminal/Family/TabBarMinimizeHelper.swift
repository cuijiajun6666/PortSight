//
//  TabBarMinimizeHelper.swift
//  PortSight
//
//  Reports whether the tab bar is minimized, so the 图库 page can show its 年 / 月 / 全部 picker in the space
//  the bar leaves free. Taken from the PhotosTB sample (Balaji Venkatesh); it finds the tab bar's two item
//  views and observes which one is hidden, and falls back to "not minimized" when it cannot find them.
//
import SwiftUI

extension TabView {
    @ContentBuilder
    func tabBarMinimizeBehaviorWithUpdate(
        isMinimized: Binding<Bool>,
        behavior: TabBarMinimizeBehavior,
        refresh: some Hashable = 0,
        error: @escaping () -> ()
    ) -> some View {
        self
            .modifier(TabBarMinimizeHelper(
                isMinimized: isMinimized,
                behavior: behavior,
                refresh: AnyHashable(refresh),
                error: error
            ))
    }
}

fileprivate struct TabBarMinimizeHelper: ViewModifier {
    @Binding var isMinimized: Bool
    var behavior: TabBarMinimizeBehavior
    /// Re-attaches the observer when it changes (e.g. the selected tab): the tab bar's item views can be
    /// rebuilt behind the observer's back (keyboard, Face ID sheet, search tab).
    var refresh: AnyHashable
    var error: () -> ()
    /// View Properties
    @State private var changeTrigger: Bool = false
    func body(content: Content) -> some View {
        content
            .background {
                /// When there is a change in the behavior simply forcing a force update for the observer!
                if changeTrigger {
                    TabBarMinimizeObserver(
                        isMinimized: $isMinimized
                    ) {
                        isMinimized = false
                        error()
                    }
                } else {
                    TabBarMinimizeObserver(
                        isMinimized: $isMinimized
                    ) {
                        isMinimized = false
                        error()
                    }
                }
            }
            .compositingGroup()
            .tabBarMinimizeBehavior(behavior)
            .onChange(of: behavior) { oldValue, newValue in
                isMinimized = false
                changeTrigger.toggle()
            }
            .onChange(of: refresh) { _, _ in
                changeTrigger.toggle()
            }
    }
}

fileprivate struct TabBarMinimizeObserver: UIViewRepresentable {
    @Binding var isMinimized: Bool
    var error: () -> ()
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            addObserver(view, context: context, attempt: 0)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {  }
    
    private func addObserver(_ view: UIView, context: Context, attempt: Int) {
        let compositingGroup = view.superview?.superview
        let tabBarController = compositingGroup?.subviews.last?.subviews.last?.next as? UITabBarController
        
        let views = (tabBarController?.tabBar.subviews ?? [])
            .filter({ !String(describing: type(of: $0)).contains("UITabBarAuxiliary") })
            .prefix(2)
        
        if let minimizedTab = views.first(where: { $0.isMinimizedTabItem }),
           let maximizedTab = views.first(where: { !$0.isMinimizedTabItem }),
           views.count == 2 && minimizedTab != maximizedTab {
            context.coordinator.addMinimizedObserver(minimizedTab)
            context.coordinator.addMaximizedObserver(maximizedTab)
        } else if attempt < 10 {
            // The tab bar may be mid-rebuild; look again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                addObserver(view, context: context, attempt: attempt + 1)
            }
        } else {
            error()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject {
        var parent: TabBarMinimizeObserver
        init(parent: TabBarMinimizeObserver) {
            self.parent = parent
        }
        
        deinit {
            minimizeObserver?.invalidate()
            maximizeObserver?.invalidate()
        }
        
        /// Properties
        var minimizeObserver: NSKeyValueObservation?
        var maximizeObserver: NSKeyValueObservation?
        
        func addMinimizedObserver(_ view: UIView) {
            minimizeObserver = view.observe(\.isHidden, options: [.new, .initial]) { [weak self] _, change in
                guard let self, let newValue = change.newValue, !newValue else { return }
                self.parent.isMinimized = true
            }
        }
        
        func addMaximizedObserver(_ view: UIView) {
            maximizeObserver = view.observe(\.isHidden, options: [.new, .initial]) { [weak self] _, change in
                guard let self, let newValue = change.newValue, !newValue else { return }
                self.parent.isMinimized = false
            }
        }
    }
}

extension UIView {
    var isMinimizedTabItem: Bool {
        frame.width == frame.height
    }
}

