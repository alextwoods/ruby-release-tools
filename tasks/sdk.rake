require 'rubygems/package'

# download the build definition and models (if they exist)
task 'download-build-inputs' do
  TrebuchetHelper.download_build_input
  TrebuchetHelper.download_models
end

# copy models into the SDK directory
task 'update-sdk-models' do
  SdkHelper.update_models
  puts "Updated models"
end

task 'update-service-json' do
  ServiceJsonUpdater.new(
    manifest_path: 'sdk/services.json',
    apis_dir: 'sdk/apis'
  ).run
  puts "Updated service.json"
end

task 'load-sdk-rakefile' do
  load('sdk/Rakefile')
end

task 'run-codegen' => ['load-sdk-rakefile'] do
  # Force to re-initialize BuildTools::Services
  # since service.json might has been updated
  BuildTools::Services = BuildTools::ServiceEnumerator.new
  Rake::Task['build'].invoke
  Rake::Task['update-readme'].invoke
  # DEPRECATED - sensitive params are now on types
  # Rake::Task['update-sensitive-params'].invoke
  Rake::Task['update-aws-sdk-dependencies'].invoke
  Rake::Task['update-partition-service-list'].invoke
  puts "Finished SDK build"
end

task 'add-changelog-entries' => ['load-sdk-rakefile'] do
  Dir.chdir('sdk') do
    changes = `git status --porcelain gems/`
    ChangelogUpdater.new(changes: changes).update_changelogs
  end
end

task 'bump-versions' => ['load-sdk-rakefile'] do
  rebuild_gems = []
  updated_gems = {}
  double_check_changelog = ['aws-sdk', 'aws-sdk-core', 'aws-sdk-resources', 'aws-sigv2', 'aws-sigv4']
  Dir.chdir('sdk') do
    Dir.glob('gems/*').each do |gem_dir|
      gem = gem_dir.split('/')[1]
      changes = `git status --porcelain #{gem_dir}`.lines
      if changes.all? { |line| line.match(/^\?\?/) } && changes != []
        new_version = GemVersionUpdater.new(gem_dir: gem_dir, new_service: true).update_version
        rebuild_gems << gem
        updated_gems[gem] = new_version if new_version
      else
        new_version = GemVersionUpdater.new(gem_dir: gem_dir, new_service: false).update_version
        if new_version
          updated_gems[gem] = new_version
          if gem.start_with?('aws-sdk-') && gem != 'aws-sdk-core' && gem != 'aws-sdk-resources'
            rebuild_gems << gem
          elsif gem == 'aws-sdk-core'
            rebuild_gems += ['aws-sdk-sts', 'aws-sdk-sso']
          end
        end
      end
    end
  end

  # write out file with updated gems
  File.write('UPDATED_VERSIONS', JSON.dump(updated_gems))

  # Update kms dependency in s3 accordingly if available
  if rebuild_gems.include? 'aws-sdk-kms'
    rebuild_gems << 'aws-sdk-s3' unless rebuild_gems.include? 'aws-sdk-s3'
    # Update s3 manifest dependency
    updater = ServiceJsonUpdater.new(
      manifest_path: 'sdk/services.json',
      apis_dir: 'sdk/apis'
    ).update_dependency({
                          'S3' => 'aws-sdk-kms'
                        })
  end

  # update dependency & rebuild gems after version bump
  # must re-initialize service again since their version have changed
  BuildTools::Services = BuildTools::ServiceEnumerator.new
  rebuild_gems.each do |gem|
    Rake::Task["build:#{gem}"].reenable
    Rake::Task["build:#{gem}"].invoke
  end
  Rake::Task['update-aws-sdk-dependencies'].reenable
  Rake::Task['update-aws-sdk-dependencies'].invoke
end

task 'test:unit'  do
  Dir.chdir('sdk') do
    cmd = Dir.glob('gems/*/spec').inject("rspec") do |cmd, path|
      cmd + " -I #{path} #{path}"
    end
    sh(cmd)
  end
end

task 'build:gems' do
  FileUtils.mkdir_p('gems')
  Dir.glob("sdk/**/*.gemspec").each do |gemspec_path|
    gem_path = ''
    Dir.chdir(File.dirname(gemspec_path)) do
      gemspec = Gem::Specification.load(File.basename(gemspec_path))
      gem_path = Gem::Package.build(gemspec)
    end
    FileUtils.mv(File.join(File.dirname(gemspec_path), gem_path), "gems/")
  end
  puts "Built gems"
end

task 'test-task' do
  puts "Running a test task!"
end

task 'test:integration' => ['load-sdk-rakefile'] do
  failures = []
  features = Dir.glob('sdk/gems/aws-sdk-simpledb/features/**/*.feature').to_a
  features.group_by { |path| path.split('/')[2] }.keys.each do |gem_name|
    sh("cucumber --retry 4 -r sdk/gems/#{gem_name}/features -r ./integ-test-config.rb sdk/gems/#{gem_name}/features --tags='not @smoke and not @veryslow'") do |ok, _|
      failures << gem_name if !ok
    end
  end

  abort("one or more test suites failed: %s" % [failures.join(', ')]) unless failures.empty?
end
