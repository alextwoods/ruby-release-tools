require 'net/https'
require 'uri'
require 'json'

module GemHelper
  class RetryableError < StandardError; end

  class << self
    MAX_RETRIES = 2

    def current_rubygems_version(gem_name)
      http = rubygems_http
      req = Net::HTTP::Get.new("/api/v1/versions/#{gem_name}/latest.json")
      call_and_retry(http, req) { |resp| JSON.parse(resp.body)['version'] }
    end

    def dependencies(gem_name)
      http = rubygems_http
      req = Net::HTTP::Get.new("/api/v1/gems/#{gem_name}.json")
      call_and_retry(http, req) { |resp| JSON.parse(resp.body)['dependencies'] }
    end

    # Uses wget because RubyGems api does not have a download
    def download(gem_name, gem_version, dir = '/tmp/gems')
      gem_path = "#{gem_name}-#{gem_version}.gem"
      unless File.exists? File.join(dir, gem_path)
        puts "Downloading gem from Rubygems: #{gem_path}"
        `wget -q -P #{dir} https://rubygems.org/downloads/#{gem_path}`
      end
      "#{dir}/#{gem_path}"
    end

    # Install a gem from a given path
    def install(gem_path, install_dir = nil, version = Gem::Requirement.default)
      Gem.install(gem_path, version, install_dir: install_dir, ignore_dependencies: true)
    end

    # Uninstall a gem given a name and version
    def uninstall(gem_name, gem_path)
      puts "uninstalling gem: #{gem_name} from #{gem_path}"
      `gem uninstall #{gem_name} -i #{gem_path} --force`
    end

    def push(gem_path)
      puts "** publishing gem: #{File.basename(gem_path)}"
      http = rubygems_http

      File.open(gem_path, 'rb') do |gem|
        req = Net::HTTP::Post.new(
          '/api/v1/gems',
          'Authorization' => Secrets.rubygems_api_key,
          'Content-Length' => File.size(gem_path).to_s,
          'Content-Type' => 'application/octet-stream'
        )
        req.body_stream = gem
        call_and_retry(http, req, &:body)
      end
    end

    def name_from_gem_path(gem_path)
      version = version_from_gem_path(gem_path)
      File.basename(gem_path).gsub("-#{version}.gem", '')
    end

    def new_version?(current, release)
      # new gems, no versions yet
      return true if current.nil? || current == 'unknown'
      return false if current == release
      cur_ver = current.split('.').map(&:to_i)
      next_ver = release.split('.').map(&:to_i)
      3.times do |i|
        return true if cur_ver[i] < next_ver[i]
        return false if cur_ver[i] > next_ver[i]
      end
      false
    end

    def version_from_gem_path(gem_path)
      File.basename(gem_path).match(/([\d]+\.[\d]+\.[\d]+)\.gem/)[1]
    end

    # Returns the path a gem has been loaded from
    # returns nil if the gem has not been required
    def loaded_from(gem)
      $LOADED_FEATURES.find { |f| f.include? "#{gem}.rb" }
    end

    private

    def rubygems_http
      http = Net::HTTP.new('rubygems.org', 443)
      http.use_ssl = true
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      http.cert_store = store
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http
    end

    # retry too much will cause rubygems throttling
    # https://github.com/rubygems/rubygems.org/issues/2081
    def call_and_retry(http, req)
      count = 0
      begin
        count += 1
        resp = nil
        http.start { resp = http.request(req) }
        case resp.code.to_i
        when 200 # ok
          return yield(resp)
        when 429 # too many request
          puts "too many requests: #{resp.body}"
          time = resp.to_hash['retry-after'].first.to_i
          if time <= 600 # <= 10 min
            puts "sleep for #{time} before retry"
            sleep(time)
            raise RetryableError,
                  "Too Many Requests, retryable after: #{time} seconds"
          else
            raise "Too Many Requests.  Unable to retry (retry-after: #{time})"
          end
        else
          msg = "unexpected #{resp.code} response from get gem dependencies\n"
          msg += resp.body
          raise msg
        end
      rescue RetryableError => e
        raise e unless count <= MAX_RETRIES

        puts "(Retry: #{count}) Retrying: #{e.message}"
        req.body.rewind
        retry
      end
    end
  end
end
