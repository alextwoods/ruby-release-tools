
require 'fileutils'

module SdkHelper

  class << self

    def update_models
      Dir.glob("models/apis/**/*").each do |path|
        next if File.directory?(path)
        out_file = path.gsub(/^models/, 'sdk')
        FileUtils.mkdir_p(File.dirname(out_file))
        FileUtils.cp(path, out_file)
      end

    end
  end
end