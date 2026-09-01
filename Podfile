platform :osx, '12.0'

use_frameworks!

target 'MiniCam' do
  pod 'VLCKit', '3.7.2'

  target 'MiniCamTests' do
    inherit! :search_paths
    pod 'VLCKit', '3.7.2'
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
    end
  end
end
