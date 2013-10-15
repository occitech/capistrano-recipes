##
# Croogo CMS deployment recipe
#
# - Depends on the CakePHP2x-Recipe
# - Add the following files to the :app_shared_files list
# 	"/Config/croogo.php",
# 	"/Config/settings.json",
# - Add the following directories to the :app_shared_dirs list
# 	"/tmp/cache/queries"
##
_cset (:croogo_plugin) { [] } # Your app specific plugins to enable / activate

namespace :croogo do
	desc "Croogo deployment"

	desc "Install Croogo"
	task :install do
		cmd = "#{latest_release}#{app_path}/Console/cake -app #{latest_release}#{app_path} Install.install"
		input = ''
		run cmd do |channel, stream, data|
			next if data.chomp == input.chomp
			print data
			channel.send_data(input = $stdin.gets) if data =~ />/
		end
	end

	desc "Activate croogo plugin"
	task :activate_plugins do
		croogo_plugin.each do |plugin|
			croogo.chmod
			cmd = "#{shared_path}/cake/lib/Cake/Console/cake -app #{latest_release}#{app_path} ext activate plugin #{plugin}"
			run cmd
		end
	end

	desc "Chmod files"
	task :chmod do
		path = "#{latest_release}#{app_path}"
		run "chmod -R 777 #{path}/Config #{path}/Test #{path}/tmp/*"
	end

	desc "Clear Croogo cache"
	task :clear_cache do
		[ '', 'acl', 'blocks', 'menus', 'nodes', 'settings', 'taxonomy', 'users' ].each { |line|
			run "mkdir -p #{shared_path}/tmp/cache/queries/#{line}"
		}
	end
end

# Uncomment this line when the production server uses Croogo too
#after "cake:clear_cache", "croogo:clear_cache", "croogo:chmod"
