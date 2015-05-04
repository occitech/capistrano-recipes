##
# APC recipe
# => convenience rules for dealing with APC in applications
##

_cset(:apc_webroot) { "" }

namespace :apc do
	desc <<-DESC
		Create a temporary PHP file to clear APC cache, call it (using curl) and removes it
		This task must be triggered AFTER the deployment to clear APC cache
	DESC
	task :clear_cache, :roles => :app do
		apc_file = "#{latest_release}#{apc_webroot}/apc_clear.php"
		curl_options = "-s"
		if !http_auth_users.to_a.empty? then
			curl_options = curl_options + " --user " + http_auth_users[0][0] + ":" + http_auth_users[0][1]
		end

		put "<?php apc_clear_cache(); apc_clear_cache('user'); ?>", apc_file, :mode => 0644
		run "curl #{curl_options} #{url_base}/apc_clear.php && rm -f #{apc_file}"
	end
end
