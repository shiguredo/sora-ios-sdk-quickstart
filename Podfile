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
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['ENABLE_BITCODE'] = 'NO'
        end
    end
end