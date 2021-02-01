
require 'aws-sdk-s3'
require 'zip'
require 'fileutils'

module TrebuchetHelper

  class << self

    def download_build_input
      puts "Getting build input"
      s3 = Aws::S3::Client.new
      s3.get_object(
        bucket: ENV['ARTIFACT_BUCKET'],
        key: "#{ENV['BUILD_ID']}/build_input.json",
        response_target: 'build_input.json'
      )
    end

    # TODO: This only works for staging and currently assumes models exist
    def download_models
      build_definition = JSON.parse(File.read('build_input.json'))
      process_feature(build_definition['trebuchet_message']["newModel"], staging: true)
    end

    private

    def process_feature(feature, staging: false)
      presigned_url = feature["c2jModels"]
      if presigned_url.nil?
        msg = "Received a feature update that contains no C2jModels."
        raise msg unless feature["featureType"].eql?("SERVICE_REGION_LAUNCH")
        return
      end
      feature_files = staging ? extract_staging_feature(feature, presigned_url)
                        : extract_feature(feature, presigned_url, feature["releaseNotes"])
    end

    def extract_feature(feature, presigned_url, i2)
      puts "TODO"
    end

    def extract_staging_feature(feature, presigned_url)
      output_file = "trebuchet-models-#{feature["serviceId"]}.zip"
      zipfile = download(output_file: output_file, presigned_url: presigned_url)
      extract_archive(zipfile, "models/apis")
    end

    def download(output_file:, presigned_url: nil, tarball_uri: nil, redirects: 0)
      raise 'too many redirects' if redirects > 3
      uri = URI(presigned_url || tarball_uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      http.cert_store = store
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.start
      http.request(Net::HTTP::Get.new(uri.request_uri, {})) do |resp|
        case resp.code.to_i
        when 200
          File.open(output_file, 'wb') do |file|
            resp.read_body do |chunk|
              file.write(chunk)
            end
          end
        when 302
          download(
            output_file: output_file,
            tarball_uri: resp.to_hash['location'][0],
            redirects: redirects + 1
          )
        else
          raise "unexpected status code: #{resp.code}\n\n#{resp.body}"
        end
      end
      http.finish
      output_file
    end


    def extract_archive(zipfile, output_dir)
      outfiles = []
      Zip::File.open(zipfile) do |archive|
        archive.each do |entry|

          filename = transform_filename(entry.name, output_dir)
          if keep?(filename)
            outfiles << filename
            FileUtils.mkdir_p(File.dirname(filename))
            puts "TREBUCHET NEW FILE: #{filename}"
            entry.extract(filename) { true }
          end
        end
      end
      outfiles
    end

    def transform_filename(archive_filename, output_dir)
      # In: output/servicename/apiversion/filename.json
      # Out: sdk/apis/servicename/apiversion/filename.json
      archive_filename.gsub(/^output/, output_dir)
    end

    def keep?(name)
      name.match(/\/api-2.json/) ||
        name.match(/\/docs-2.json/) ||
        name.match(/\/examples-1.json/) ||
        name.match(/\/paginators-1.json/) ||
        name.match(/\/resources-1.json/) ||
        name.match(/\/waiters-2.json/) ||
        name.match(/\/smoke.json/)
    end

  end
end
