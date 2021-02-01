require 'json'

class GemVersionUpdater

  def initialize(gem_dir:, new_service:)
    @gem_dir = gem_dir
    @changelog = BuildTools::Changelog.new(path: "#{gem_dir}/CHANGELOG.md")
    @new_service = new_service
  end

  # @return [String]
  attr_reader :gem_dir

  # @return [BuildTools::Changelog]
  attr_reader :changelog

  # @return [Boolean]
  attr_reader :new_service

  # @return [String] the new version or nil if there are no updates
  def update_version
    changes = changelog.unreleased_changes.entries
    if changes.empty?
      nil
    else
      version_path = "#{gem_dir}/VERSION"
      next_version = compute_next_version(
        current_version: File.read(version_path).strip,
        changes: changes
      )
      puts "Bumping #{version_path} to #{next_version}"
      changelog.version_unreleased_changes(version: next_version)
      File.open(version_path, 'w') { |file| file.write(next_version + "\n") }
      next_version
    end
  end

  def one_time_ga_bump
    version_path = "#{gem_dir}/VERSION"
    next_version = compute_ga_version(
      current_version: File.read(version_path).strip
    )
    puts " bumping #{version_path} to #{next_version}"
    changelog.version_unreleased_changes(version: next_version)
    File.open(version_path, 'w') { |file| file.write(next_version + "\n") }
  end

  private

  def compute_ga_version(current_version:)
    x, _, _, label = parse_version(current_version)
    if label
      "#{x}.0.0"
    else
      raise "No label in #{current_version}, crash!"
    end
  end

  def compute_next_version(current_version:, changes:)
    if @new_service
      current_version
    elsif changes.any?(&:point?)
      increase_point_level(current_version)
    else
      increase_patch_level(current_version)
    end
  end

  def increase_point_level(version)
    x, y, z, label = parse_version(version)
    if label
      "#{x}.#{y}.#{z}#{increase_label(label)}"
    else
      x.zero? ? "1.0.0" : "#{x}.#{y + 1}.0"
    end
  end

  def increase_patch_level(version)
    x, y, z, label = parse_version(version)
    if label
      "#{x}.#{y}.#{z}#{increase_label(label)}"
    else
      "#{x}.#{y}.#{z + 1}"
    end
  end

  def parse_version(version)
    matches = version.match(/^(\d+)\.(\d+)\.(\d+)(\..+)?$/)
    [
      matches[1].to_i, # x
      matches[2].to_i, # y
      matches[3].to_i, # z
      matches[4]       # optional string, e.g. ".preview" or ".rc1"
    ]
  end

  # converts strings like ".preview" into ".preview2" or ".rc2" into ".rc3"
  def increase_label(label)
    if label.match(/^(\..+?)(\d+)?$/)
      "#{$1}#{$2.to_i + 1}"
    else
      "#{$1}2"
    end
  end

end
