
# download the build definition and models (if they exist)
task 'download-build-inputs' do
  TrebuchetHelper.download_build_input
  TrebuchetHelper.download_models
end

task 'test-task' do
  puts "Running a test task!"
end