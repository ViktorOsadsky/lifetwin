require 'xcodeproj'
root=File.expand_path(ARGV.fetch(0))
p=Xcodeproj::Project.open(root+'/Runner.xcodeproj')
runner=p.targets.find{|t|t.name=='Runner'}
t=p.targets.find{|x|x.name=='Demo133UITests'} || p.new_target(:ui_test_bundle,'Demo133UITests',:ios,'15.0')
t.add_dependency(runner) if t.dependencies.empty?
g=p.main_group.find_subpath('Demo133UITests',false) || p.main_group.new_group('Demo133UITests','Demo133UITests')
g.new_file('Demo133UITests.swift').tap{|f|t.source_build_phase.add_file_reference(f)} if t.source_build_phase.files.empty?
t.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='com.danielqi.lifesim.demo133current.Demo133UITests'
 c.build_settings['TEST_TARGET_NAME']='Runner'
 c.build_settings['PRODUCT_NAME']='$(TARGET_NAME)'
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['CODE_SIGNING_ALLOWED']='NO'
 c.build_settings['CLANG_ENABLE_MODULES']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
end
p.save
s=Xcodeproj::XCScheme.new
s.add_build_target(runner);s.add_test_target(t)
s.test_action.build_configuration='Debug';s.set_launch_target(runner)
s.launch_action.build_configuration='Debug'
s.save_as(p.path,'Demo133Acceptance',true)
