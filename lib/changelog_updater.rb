require 'json'

class ChangelogUpdater

  def initialize(changes:)
    @changes = {}
    changes.lines.each do |line|
      matches = line.match(/gems\/(.+?)\/(.+)?$/)
      gem_name = matches[1]
      path = matches[2]
      @changes[gem_name] ||= []
      @changes[gem_name] << path if path
    end
  end

  def update_changelogs
    @changes.each_pair do |gem_name, files|
      add_changelog_entries(gem_name: gem_name, files: files)
    end
  end

  private

  def add_changelog_entries(gem_name:, files:)
    case gem_name
    when 'aws-sdk-resources' then update_aws_sdk_resources_changelog
    when 'aws-sdk-core'      then update_core_changelog(files: files)
    when 'aws-partitions'    then update_partitions_changelog(files: files)
    else update_service_gem_changelog(gem_name: gem_name, files: files)
    end
  end

  def update_aws_sdk_resources_changelog
    changelog = BuildTools::Changelog.new(path: 'gems/aws-sdk-resources/CHANGELOG.md')
    `git diff gems/aws-sdk-resources/lib/aws-sdk-resources.rb`.lines.each do |line|
      if line.match(/^\+  autoload :\w+, '(.+)'$/)
        changelog.add_entry(
          type: :feature,
          text: "Added a dependency on the new `#{$1}` gem."
        )
      end
    end
  end

  def update_core_changelog(files:)
    changelog  = BuildTools::Changelog.new(path: 'gems/aws-sdk-core/CHANGELOG.md')
    sts_entry = false
    sso_entry = false
    files.each do |path|
      case path
      when 'CHANGELOG.md' # ignore
      when 'lib/aws-sdk-core/log/param_filter.rb'
        changelog.add_entry(
          type: :feature,
          text: "Updated the list of parameters to filter when logging."
        )
      when /lib\/aws-sdk-sts/
        # Avoid duplicate STS feature entry
        unless sts_entry
          changelog.add_entry(
            type: :feature,
            text: "Updated Aws::STS::Client with the latest API changes."
          )
          sts_entry = true
        end
      when /lib\/aws-sdk-sso/
        # Avoid duplicate SSO feature entry
        unless sso_entry
          changelog.add_entry(
            type: :feature,
            text: "Updated Aws::SSO::Client with the latest API changes."
          )
          sso_entry = true
        end
      else
        raise "unexpected change in gems/aws-sdk-core/#{path}"
      end
    end
  end

  def update_partitions_changelog(files:)
    changelog = BuildTools::Changelog.new(path: 'gems/aws-partitions/CHANGELOG.md')
    if files.include?('lib/aws-partitions.rb')
      # new services have been added
      `git diff -U0 gems/aws-partitions/lib/aws-partitions.rb`.lines.each do |line|
        if line.match(/^\+\s+'(.+?)' => '.+?'/)
          changelog.add_entry(
            type: :feature,
            text: "Added support for enumerating regions for `Aws::#{$1}`."
          )
        end
      end
    else
      changelog.add_entry(
        type: :feature,
        text: 'Updated the partitions source data the determines the AWS service regions and endpoints.'
      )
    end
  end

  def update_service_gem_changelog(gem_name:, files:)
    changelog = BuildTools::Changelog.new(path: "gems/#{gem_name}/CHANGELOG.md")
    if files.empty?
      # band new service
      changelog.add_unreleased_changes_section
      changelog.add_entry(
        type: :feature,
        text: "Initial release of `#{gem_name}`."
      )
    else
      if files.include?("CHANGELOG.md")
        # 1.regular release API updates
        #   entry has been added when unpacking release
        # 2.merged PRs (feature, bug fix etc.)
        #   entry has been added when merging PR
      else
        # code-gen emitted changes
        changelog.add_entry(
          type: :feature,
          text: "Code Generated Changes, see `./build_tools` or `aws-sdk-core`'s CHANGELOG.md for details."
        )
      end
    end
  end
end
