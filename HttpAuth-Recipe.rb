##
# HTTP Authentification deployment Recipe
# => Add htaccess password protection when deploying, with the correct htpassword file for the passed users
##
_cset (:http_auth_users) {[
	["admin", "password"]
]}
_cset (:http_auth_path) { "" } # Path of the directory to add http auth, from the release root

namespace :httpAuth do

	desc <<-DESC
		Generates / updates .htaccess and .htpasswd files with the credentials passed in parameter
		Inspired from: https://gist.github.com/805879
	DESC
	task :protect do
		htpasswdFile = "#{latest_release}#{http_auth_path}/.htpasswd"
		htpasswdContent = http_auth_users.inject("") { |content, user|
			content = content + user[0] + ":" + user[1].crypt("httpauth") + "\n"
		}
		put htpasswdContent, htpasswdFile, :mode => 0644

		[
			'',
			'AuthType Basic',
			'AuthName "Restricted"',
			"AuthUserFile \"#{htpasswdFile}\"",
			'Require valid-user'
		].each { |line| run "echo '#{line}' >> #{latest_release}#{http_auth_path}/.htaccess" }
	end
end
