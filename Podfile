source 'https://cdn.cocoapods.org/'
source 'https://github.com/shiguredo/sora-ios-sdk-specs.git'

platform :ios, '13.0'

target 'SoraQuickStart' do
  use_frameworks!
  pod 'Sora', :git => 'https://github.com/shiguredo/sora-ios-sdk.git', :branch => 'develop'

  pod 'SwiftLint'
  pod 'SwiftFormat/CLI'

end

post_install do |installer|
    target_names = ["Sora", "Pods-SoraQuickStart", "WebRTC"]

    target_names.each do |target_name|
        # 変更対象のターゲット を探す
        pods_target = installer.pods_project.targets.find{ |target| target.name == target_name }
        unless pods_target
            raise ::Pod::Informative, "Failed to find '" << target_name << "' target"
        end

        # ビルド設定を追加
        pods_target.build_configurations.each do |config|
            config.build_settings['ENABLE_BITCODE'] = 'NO'
        end
    end
end