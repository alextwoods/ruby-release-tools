require 'fileutils'

# This task is a pipeline approval workflow. It is executed in
# the prod/release state of the release pipeline after gem publishing.
# This step verifies that all of the gems are working prior to publishing.
task 'verify-gems' do
  svc_gems = []
  special_gems = {}

  Dir.glob("gems/**/*.gem").each do |path|
    gem_path = path.split('/')[-1]
    # Do not check pre-release or release candidate gems.
    next if gem_path.include?('.pre.gem') || gem_path.include?('.rc')

    version = GemHelper.version_from_gem_path(gem_path)
    gem_name = gem_path.split("-#{version}.gem")[0]

    cur_ver = GemHelper.current_rubygems_version(gem_name)
    new_version = GemHelper.new_version?(cur_ver, version)

    if new_version
      puts "*** Gem #{gem_name} has a new version, using #{path}"
    else
      path = GemHelper.download(gem_name, version)
    end

    case gem_name
    when 'aws-partitions'
      special_gems[:partitions] = path
    when 'aws-eventstream'
      special_gems[:eventstream] = path
    when 'aws-sigv2'
      special_gems[:sigv2] = path
    when 'aws-sigv4'
      special_gems[:sigv4] = path
    when 'aws-sdk-kms'
      special_gems[:kms] = path
    when 'aws-sdk-core'
      special_gems[:core] = path
    when 'aws-sdk'
      special_gems[:sdk] = path
    when 'aws-sdk-resources'
      special_gems[:resources] = path
    else
      svc_gems << path
    end
  end

  # this gem isn't in the repo
  jmespath = GemHelper.download('jmespath', '1.4.0')
  GemHelper.install(jmespath)

  # we depend on an old verions of event-stream :-(
  special_gems[:eventstream] = GemHelper.download('aws-eventstream', '1.0.3')

  test_install_dir = Dir.mktmpdir
  GemHelper.install(special_gems[:partitions], test_install_dir)
  GemHelper.install(special_gems[:eventstream], test_install_dir)
  GemHelper.install(special_gems[:sigv2], test_install_dir)
  GemHelper.install(special_gems[:sigv4], test_install_dir)

  new_core_install_dir = Dir.mktmpdir
  GemHelper.install(special_gems[:core], new_core_install_dir)

  # kms depends on s3
  GemHelper.install(special_gems[:kms], test_install_dir)

  svc_gems.each do |gem|
    GemHelper.install(gem, test_install_dir)
  end

  GemHelper.install(special_gems[:resources], test_install_dir)
  GemHelper.install(special_gems[:sdk], test_install_dir)

  require 'jmespath'

  Gem::Specification.dirs = test_install_dir

  # Verify require of the gems
  pid = fork do
    $LOAD_PATH.unshift *Dir.glob("#{test_install_dir}/gems/**/lib")
    $LOAD_PATH.unshift *Dir.glob("#{new_core_install_dir}/gems/**/lib")

    Gem::Specification.map(&:name).each do |gem|
      next unless gem.start_with?('aws-')
      require gem
      puts "Required: #{gem} from: #{GemHelper.loaded_from(gem)}"
    end
  end

  Process.wait(pid)
  exit_status = $?
  raise "Failed to load all gems" unless exit_status.success?

  FileUtils.rm_rf(new_core_install_dir)

  # Test older core with new service gems
  svc_gems.each do |gem|
    Gem::Specification.dirs = test_install_dir

    gem_name = GemHelper.name_from_gem_path(gem)
    gem_specs = Gem::Specification.select { |s| s.name == gem_name }

    minimum_core_version = gem_specs.first
                                    .dependencies.find { |d| d.name == 'aws-sdk-core' }
                                    .requirement.requirements.find { |op, ver| op != '~>' }.last.version

    # don't download the core gem if the minimum version will be released now
    core_path = if minimum_core_version == GemHelper.version_from_gem_path(special_gems[:core])
                  special_gems[:core]
                else
                  GemHelper.download('aws-sdk-core', minimum_core_version)
                end

    old_core_install_dir = Dir.mktmpdir
    GemHelper.install(core_path, old_core_install_dir)

    pid = fork do
      $LOAD_PATH.unshift *Dir.glob("#{test_install_dir}/gems/**/lib")
      $LOAD_PATH.unshift *Dir.glob("#{old_core_install_dir}/gems/**/lib")

      require gem_name
      puts "Required: #{gem} with core version #{minimum_core_version} from: "\
           "#{GemHelper.loaded_from(gem_name)} and core from: "\
           "#{GemHelper.loaded_from('aws-sdk-core')}"

      FileUtils.rm_rf(old_core_install_dir)
    end
    Process.wait(pid)
    exit_status = $?
    raise "Failed to load #{gem_name}" unless exit_status.success?

  end

  FileUtils.rm_rf(test_install_dir)
end
