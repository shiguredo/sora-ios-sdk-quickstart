source 'https://cdn.cocoapods.org/'
source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '12.1'

target 'SoraQuickStart' do
  use_frameworks!
  pod 'Sora', '2021.2.1'

  pod 'SwiftLint'
  pod 'SwiftFormat/CLI'

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '10.0'
      end
    end
  end

# シミュレーターのビルド用の設定です。 arm64 を除いてビルドします。
# Sora iOS SDK はシミュレーターでのビルドと動作をサポートしませんので、
# あくまで参考例としてご利用ください。
#
# post_install do |installer|
#   installer.pods_project.build_configurations.each do |config|
#     config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = "arm64"
#   end
end
