
task 'publish:git-release' do
  puts "Does the GH Token match? #{ENV['AWS_SDK_FOR_RUBY_GH_TOKEN'].include?('580ddc')}"
  Dir.chdir('sdk') {
    Rake.sh("git remote add upstream https://alextwoods:#{ENV['AWS_SDK_FOR_RUBY_GH_TOKEN']}@github.com/alextwoods/aws-sdk-ruby.git")
    Rake.sh("git fetch")
    Rake.sh("git config --global user.email 'alextwoods@outlook.com'")
    Rake.sh("git config --global user.name 'Alex Woods'")
    Rake.sh("git checkout -b staging-build")
    Rake.sh("git commit -a -m 'Test staging build'")
    Rake.sh("git push --set-upstream upstream staging-build")
  }
end