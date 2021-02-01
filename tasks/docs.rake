require 'yard'
require 'fileutils'

task 'docs' do
  FileUtils.mkdir_p('docs')
  docs_out_dir = File.expand_path('docs')
  Dir.chdir('sdk/') do
    ENV['DOCSTRINGS'] = '1'
    ENV['SITEMAP_BASEURL'] = 'http://docs.aws.amazon.com/sdk-for-ruby/v3/api/'
    ENV['BASEURL'] = 'http://docs.aws.amazon.com/'
    yardoc = YARD::CLI::Yardoc.new
    yardoc.run("--output-dir=#{docs_out_dir}")
  end
  # TODO: add redirects and such
end