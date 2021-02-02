
task 'publish:git-release' do
  `git remote add origin https://alextwoods:#{ENV['AWS_SDK_FOR_RUBY_GH_TOKEN']}@github.com/alextwoods/aws-sdk-ruby.git`
  `git checkout -b staging-build --track upstream/staging-build`
  `git commit -a -m 'Test staging build'`
end