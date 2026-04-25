#!/usr/bin/env ruby
# Adds Adapty + AdaptyUI Swift Package dependencies to the LiboLibo Xcode project.
# Idempotent — safe to re-run.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../LiboLibo.xcodeproj', __dir__)
TARGET_NAME = 'LiboLibo'
PACKAGE_URL = 'https://github.com/adaptyteam/AdaptySDK-iOS'
PACKAGE_MIN_VERSION = '3.0.0'
PRODUCT_NAMES = %w[Adapty AdaptyUI]

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }
abort("Target #{TARGET_NAME} not found") unless target

package_ref = project.root_object.package_references.find { |r| r.repositoryURL == PACKAGE_URL }
unless package_ref
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = PACKAGE_URL
  package_ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => PACKAGE_MIN_VERSION }
  project.root_object.package_references << package_ref
end

PRODUCT_NAMES.each do |product_name|
  if target.package_product_dependencies.any? { |d| d.product_name == product_name }
    next
  end
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = package_ref
  dep.product_name = product_name
  target.package_product_dependencies << dep

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  target.frameworks_build_phase.files << build_file
end

target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_ADAPTY_PUBLIC_SDK_KEY'] = '$(ADAPTY_PUBLIC_SDK_KEY)'
  config.build_settings['ADAPTY_PUBLIC_SDK_KEY'] ||= ''
end

project.save
puts "OK: package + products added"
