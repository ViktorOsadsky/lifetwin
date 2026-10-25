# Run only inside an isolated /private/tmp app copy. Requires installed xcodeproj gem.
require 'xcodeproj'
require 'rexml/document'
require 'pathname'
root = File.realpath(ARGV.fetch(0))
abort 'Use an isolated /private/tmp app copy' unless root.start_with?('/private/tmp/')
p = Xcodeproj::Project.open(root + '/ios/Runner.xcodeproj')
abort 'Target already exists' if p.targets.any? { |t| t.name == 'A11y134UITests' }
runner = p.targets.find { |t| t.name == 'Runner' }
runner.build_configurations.each { |c| c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.danielqi.lifesim.a11y134' }
t = p.new_target(:ui_test_bundle, 'A11y134UITests', :ios, '27.0')
t.add_dependency(runner)
g = p.main_group.new_group('A11y134UITests', 'A11y134UITests')
g.new_file('A11y134UITests.m').tap { |f| t.source_build_phase.add_file_reference(f) }
t.build_configurations.each do |c|
 c.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER'=>'com.danielqi.lifesim.a11y134.A11y134UITests',
 'PRODUCT_NAME'=>'$(TARGET_NAME)','TEST_TARGET_NAME'=>'Runner','GENERATE_INFOPLIST_FILE'=>'YES',
 'CODE_SIGNING_ALLOWED'=>'NO','CLANG_ENABLE_MODULES'=>'YES')
end
p.save
# Preserve Flutter's Prepare preaction; a fresh bare Xcode scheme is insufficient.
path=root+'/ios/Runner.xcodeproj/xcshareddata/xcschemes/'
doc=REXML::Document.new(File.read(path+'Runner.xcscheme'))
test=doc.elements['Scheme/TestAction']
test.delete_element('Testables')
ref=test.add_element('Testables').add_element('TestableReference',{'skipped'=>'NO'})
ref.add_element('BuildableReference',{'BuildableIdentifier'=>'primary','BlueprintIdentifier'=>t.uuid,
 'BuildableName'=>'A11y134UITests.xctest','BlueprintName'=>'A11y134UITests','ReferencedContainer'=>'container:Runner.xcodeproj'})
File.write(path+'A11y134Acceptance.xcscheme',doc.to_s)
