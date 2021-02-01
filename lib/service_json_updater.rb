require 'json'

class ServiceJsonUpdater

  def initialize(manifest_path:, apis_dir:)
    @manifest_path = manifest_path
    @apis_dir = apis_dir
  end

  # @return [String]
  attr_reader :manifest_path

  # @return [String]
  attr_reader :apis_dir

  def run
    services = filter_to_latest_api_versions(possible_services)
    manifest = load_manifest

    raise_on_missing_services!(
      services: services,
      manifest: manifest
    )

    apply_services_to_manifest(
      services: services,
      manifest: manifest,
      )

    write_manifest(manifest: sort_manifest(manifest))
  end

  def update_dependency(pairs)
    manifest = load_manifest
    pairs.each do |module_name, gem|
      version_file = File.read("sdk/gems/#{gem}/VERSION").strip
      version = version_file.match(/^\d+\.\d+\.\d+$/) ?
                  "~> #{version_file.split('.')[0]}" :
                  version_file
      manifest[module_name]['dependencies'][gem] = version
    end
    write_manifest(manifest: sort_manifest(manifest))
  end

  def update_changelog(model, notes)
    return if notes.nil? || notes.empty?
    Dir.chdir(apis_dir) do
      svc = PossibleService.new(model: model)
      gem_name = "aws-sdk-" + svc.module_name.downcase
      changelog_path = "../gems/#{gem_name}/CHANGELOG.md"
      BuildTools::Changelog.new(
        path: changelog_path
      ).add_entry(
        type: :feature,
        text: notes
      ) if File.exists?(changelog_path)
    end
  end

  private

  # computes possible services by crawling the apis directory
  def possible_services
    override_count = PossibleService::MODULE_NAME_OVERRIDES.length
    svc_pool = Dir.chdir(apis_dir) do
      Dir.glob('*/*').inject([]) do |services, model|
        svc = PossibleService.new(model: model)
        override_count -= 1 if svc.override_flag
        services << svc
      end
    end
    msg = 'When mapping services with models, not all override entries in PossibleService::MODULE_NAME_OVERRIDES are checked.'
    raise msg unless override_count.zero?
    svc_pool
  end

  # Some services, such as EC2, RDS, etc, have multiple API versions.
  # This method filters the possible service list to only include one
  # version of each service, the most recent version
  def filter_to_latest_api_versions(services)
    services.sort_by { |svc| [ svc.module_name, svc.api_version ] }.inject({}) do |hash, svc|
      hash[svc.module_name] = svc
      hash
    end.values
  end

  # Ensure that every service already represented in the services.json
  # manifest is in the list of possible services.
  # ensure the API model for a service doesn't go missing
  def raise_on_missing_services!(services:, manifest:)
    missing = manifest.keys - services.map(&:module_name)
    if !missing.empty?
      msg = "one or more services list in the services.json no longer have API "
      msg << "models: %s" % [missing.join(', ')]
      raise msg
    end
  end

  def apply_services_to_manifest(services:, manifest:)
    services.each do |svc|
      manifest[svc.module_name] ||= {}
      manifest[svc.module_name]['models'] = svc.model
    end
  end

  def sort_manifest(manifest)
    manifest.keys.sort.inject({}) do |hash, key|
      hash[key] = manifest[key]
      hash
    end
  end

  def load_manifest
    JSON.load(File.read(manifest_path))
  end

  def write_manifest(manifest:)
    File.open(manifest_path, 'wb') do |file|
      file.write(JSON.pretty_generate(manifest, indent: '  '))
      file.write("\n")
    end
  end

  class PossibleService

    MODULE_NAME_OVERRIDES = {
      "lambda/2014-11-11" => 'LambdaPreview',
      "runtime.lex/2016-11-28" => "Lex",
      "states/2016-11-23" => "States",
    }

    def initialize(model:)
      api = load_api(path: "#{model}/api-2.json")
      @override_check = false
      @module_name = compute_module_name(model: model, api: api)
      @api_version = compute_api_version(api: api)
      @model = model
    end

    # @return [String]
    attr_reader :module_name

    # @return [String]
    attr_reader :api_version

    # @return [String]
    attr_reader :model

    # @return [Boolean]
    attr_reader :override_flag

    private

    def compute_module_name(model:, api:)
      if MODULE_NAME_OVERRIDES.key?(model)
        @override_flag = true
        MODULE_NAME_OVERRIDES[model]
      else
        metadata = api.fetch('metadata')
        name = metadata.fetch('serviceAbbreviation', metadata.fetch('serviceFullName'))
        name = name.gsub(/\bv(\d)\b/, 'V\1')           # convert suffixes like v2 to V2
        name = name.gsub(/\W+/, '').gsub(/_/, '')      # make it constant safe
        name = name.sub(/^AWS/, '').sub(/^Amazon/, '') # remove AWS/Amazon prefixes
        name[0] = name.upcase[0]
        name
      end
    end

    def compute_api_version(api:)
      api.fetch('metadata').fetch('apiVersion')
    end

    def load_api(path:)
      if File.exists?(path)
        JSON.load(File.open(path, 'rb') { |file| file.read })
      else
        msg = "unable to bootstrap #{File.dirname(path)} service; "
        msg << "missing required file #{File.basename(path)}"
        raise msg
      end
    end
  end
end
