//
//  AppRouter.swift
//  Sordello
//
//  Created by Jonas Barsten on 12/12/2025.
//

import SwiftUI

// 1. Define your possible navigation routes as a Hashable enum or struct
enum AppRoute: Hashable {
    case liveSetDetail(LiveSet)
    case liveSetByPath(path: String)
}

// 2. Create an Observable Router class to manage the navigation path
@Observable
final class AppRouter {
    var path = NavigationPath()
    
    func push(_ route: AppRoute) {
        path.append(route)
    }
    
    func pop() {
        path.removeLast()
    }
    
    func popToRoot() {
        path = NavigationPath()
    }
}
