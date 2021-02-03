
task 'publish:git-release' do
  Dir.chdir('sdk') do
    `git remote add upstream https://alextwoods:#{ENV['AWS_SDK_FOR_RUBY_GH_TOKEN']}@github.com/alextwoods/aws-sdk-ruby.git`
    `git checkout -b staging-build`
    `git commit -a -m 'Test staging build'`
    `git push --set-upstream upstream staging-build`
  end
end