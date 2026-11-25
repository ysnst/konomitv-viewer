import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func sceneDidBecomeActive(_ scene: UIScene) {
        WatchedHistoryStore.shared.setActive(true)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        WatchedHistoryStore.shared.setActive(false)
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // 回線の区分 (Wi-Fi / モバイル回線) の見張りは起動時から始めておく
        // (再生を始めるときに、その時点の区分で画質を決めるため)。
        _ = NetworkMonitor.shared
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        // 接続先 URL が未設定なら、まず入力画面を出す。
        if SettingsStore.shared.isConfigured {
            window.rootViewController = makeTabBarController()
        } else {
            window.rootViewController = makeSetupController()
        }
        window.makeKeyAndVisible()
    }

    private func makeSetupController() -> UIViewController {
        let settings = SettingsViewController(mode: .setup) { [weak self] in
            self?.window?.rootViewController = self?.makeTabBarController()
        }
        return UINavigationController(rootViewController: settings)
    }

    private func makeTabBarController() -> UIViewController {
        // 下部バーは標準の UITabBar ではなく MainTabBarController の自前バーを使う
        // (標準バーは新しい iOS で浮いた丸いガラス風に描かれてしまうため)。
        // MainTabBarController は UITabBarController ではなく、4つの
        // ナビゲーション画面を子に持つただのコンテナ画面で、標準タブバーは
        // 存在自体が無い (第9弾で「隠す」方式から置き換えた)。
        // タブの題名とアイコンは setTabs でまとめて渡す。
        let tabBarController = MainTabBarController()

        // アイコンは Web 版が使う Fluent アイコンの公式素材そのものを使う。
        // Microsoft 公式リポジトリ (microsoft/fluentui-system-icons) の iOS 用
        // .imageset を Assets.xcassets に取り込んである:
        // ビデオをみる = movies-and-tv-20-regular、テレビをみる = tv-20-regular、
        // マイページ = person-20-regular (いずれも Web 版の下部ナビと同じもの)。
        // 録画予約 = timer-16-regular (Web 版の下部ナビの録画予約リンクと同じもの。
        // 素材がまだ取り込めていないため、当面は近い形の標準アイコンで受ける)。
        // 番組表はタブから外れ、生放送一覧の浮きボタンから重ねて開く画面になった
        // (番組表・予約の第2段)。
        // 素材は template 指定済みで、色はバー側の tint で切り替わる。
        // 表示の大きさ (30px) はバー側 (TabBarItemView) が持つ。
        // 万一素材が読み込めなかった場合だけ、近い形の標準アイコンで受ける。
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        let videosImage = UIImage(named: "ic_fluent_movies_and_tv_20_regular")
            ?? UIImage(systemName: "clapperboard", withConfiguration: iconConfig)
            ?? UIImage(systemName: "film", withConfiguration: iconConfig)
        let liveImage = UIImage(named: "ic_fluent_tv_20_regular")
            ?? UIImage(systemName: "tv", withConfiguration: iconConfig)
        let reservationsImage = UIImage(named: "ic_fluent_timer_16_regular")
            ?? UIImage(systemName: "timer", withConfiguration: iconConfig)
        let mypageImage = UIImage(named: "ic_fluent_person_20_regular")
            ?? UIImage(systemName: "person", withConfiguration: iconConfig)

        // タブの表示名は Web 版の表現に合わせる:
        // テレビをみる / ビデオをみる / 録画予約 / マイページ。マイページの中身は
        // マイページ化の第1回で入口一覧画面 (MyPageViewController) になり、
        // 設定画面はその「設定」の入口の先に移った。
        // Web 版の下部ナビには番組表は無く録画予約があるため、それに合わせた
        // (本人の指示、2026-11-23)。番組表は生放送一覧から重ねて開く。
        let videos = UINavigationController(rootViewController: VideoListViewController())
        let live = UINavigationController(rootViewController: LiveListViewController())
        let reservations = UINavigationController(rootViewController: ReservationListViewController())
        let mypage = UINavigationController(rootViewController: MyPageViewController())

        // タブの並びは テレビをみる → ビデオをみる → 録画予約 → マイページ。
        // タブ番号はこの並びで テレビをみる = 0、ビデオをみる = 1、
        // 録画予約 = 2、マイページ = 3 になる
        // (各画面の selectedIndex の指定はこの番号に合わせること)。
        // 起動時に最初に開くタブは、今までと同じ録画タブのままにする
        // (並びだけ変え、起動時の開き方は変えない)。
        // makeRoot は、表示の大きさが変わったときに先頭画面を作り直す
        // ための手順 (上の初期表示と同じ画面を新規に作る)。
        tabBarController.setTabs([
            (controller: live, title: "テレビをみる", image: liveImage,
             makeRoot: { LiveListViewController() }),
            (controller: videos, title: "ビデオをみる", image: videosImage,
             makeRoot: { VideoListViewController() }),
            (controller: reservations, title: "録画予約", image: reservationsImage,
             makeRoot: { ReservationListViewController() }),
            (controller: mypage, title: "マイページ", image: mypageImage,
             makeRoot: { MyPageViewController() }),
        ], initialIndex: 1)
        return tabBarController
    }
}
