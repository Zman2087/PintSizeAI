#!/usr/bin/env ruby
# Adds new Swift files to the Runner target in Runner.xcodeproj

require 'xcodeproj'

proj_path = File.join(__dir__, '..', 'ios', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(proj_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }
abort('Runner target not found') unless runner_target

runner_group = project.main_group['Runner']
abort('Runner group not found') unless runner_group

# Files to add (relative to ios/Runner/)
new_files = ['CloudSyncPlugin.swift']

new_files.each do |filename|
  full_path = File.join(__dir__, '..', 'ios', 'Runner', filename)
  next unless File.exist?(full_path)

  # Skip if already referenced
  already = runner_group.files.any? { |f| f.path == filename }
  if already
    puts "Already in project: #{filename}"
    next
  end

  file_ref = runner_group.new_reference(filename)
  runner_target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{filename}"
end

project.save
puts 'Project saved.'
