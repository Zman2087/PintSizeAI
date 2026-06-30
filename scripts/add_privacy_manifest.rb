#!/usr/bin/env ruby
# Adds PrivacyInfo.xcprivacy to the Runner target's resources.
require 'xcodeproj'

proj_path = File.join(__dir__, '..', 'ios', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(proj_path)
target = project.targets.find { |t| t.name == 'Runner' }
abort('Runner target not found') unless target
group = project.main_group['Runner']
abort('Runner group not found') unless group

fname = 'PrivacyInfo.xcprivacy'
already = group.files.any? { |f| f.path == fname }
if already
  puts "Already referenced: #{fname}"
else
  ref = group.new_reference(fname)
  target.resources_build_phase.add_file_reference(ref)
  puts "Added resource: #{fname}"
end
project.save
puts 'Saved.'
