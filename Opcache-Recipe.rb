##
# Opcache recipe
# => convenience rules for dealing with opcode cache in PHP5.5+ applications using opcache (Zend Optimizer+)
##

_cset(:opcache_webroot) { "" }

namespace :opcache do
	desc <<-DESC
		Create a temporary PHP file to clear cache, call it (using curl) and removes it
		This task must be triggered AFTER the deployment to clear cache
	DESC
	task :clear_cache, :roles => :app do
		opcache_file = "#{current_release}#{opcache_webroot}/opcache_clear.php"
		curl_options = "-s"
		if !http_auth_users.to_a.empty? then
			curl_options = curl_options + " --user " + http_auth_users[0][0] + ":" + http_auth_users[0][1]
		end

		put "<?php opcache_reset(); ?>", opcache_file, :mode => 0644
		run "curl #{curl_options} #{url_base}/opcache_clear.php && rm -f #{opcache_file}"
	end
end