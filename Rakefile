require_relative 'lib/trebuchet_helper'
require_relative 'lib/service_json_updater'
require_relative 'lib/sdk_helper'
require_relative 'lib/changelog_updater'
require_relative 'lib/gem_version_updater'

Dir.glob('tasks/**/*.rake').each do |task_file|
  load(task_file)
end

# Top level task for the codegen build stage
task 'run-sdk-build' => [
  'update-sdk-models',
  'update-service-json',
  'run-codegen',
  'add-changelog-entries',
  'bump-versions',
  'test:unit',
  'build:gems'
]
