namespace :modman do
  task :deploy_all do
    run "cd #{latest_release} && vendor/colinmollenhour/modman/modman deploy-all --force"
  end
end