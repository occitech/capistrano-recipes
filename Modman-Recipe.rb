namespace :modman do
  task :deploy_all do
    run "cd #{latest_release} && $(#{composer_bin} config vendor-dir)/colinmollenhour/modman/modman deploy-all --force --copy"
  end
end
