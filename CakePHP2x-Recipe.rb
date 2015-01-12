##
# CakePHP2.x deployment recipe
#		TODO Implement a way to revert migrations given the map.php files of a previous release
#		TODO Make a difference between tmp files and others
#		TODO Give a way to the application to define its own custom directories
##
_cset (:app_symlinks) { [
	"/webroot/cache_css", "/webroot/cache_js",
	"/tmp"
] }
_cset(:app_shared_dirs) { ["/Config", "/tmp/cache/models", "/tmp/cache/persistent", "/tmp/sessions", "/tmp/logs", "/tmp/tests"] }
_cset(:app_shared_files) { ["/Config/database.php"] }

_cset(:cake_repo) { "git://github.com/cakephp/cakephp.git" }
_cset(:cake_branch) { "master" }
_cset(:cake_migrations) { ['app'] }
_cset(:cake_binary) { "/cake/lib/Cake/Console/cake" }
_cset(:app_path) { "" } # path of your "app" directory from the base of the repository without trailing slash

_cset(:php_bin) { "php" }
_cset(:composer_bin) { false }
_cset(:composer_options) { "--no-scripts --verbose --prefer-dist --no-dev" }

# Used by the interactive database creation prompt
def defaults(val, default)
	val = default if (val.empty?)
	val
end


def get_database_credentials
	config_file = capture "cat #{current_release}#{app_path}/Config/database.php"
	row_credentials= config_file.scan(/'(?<key>\w+)'\s=>\s'(?<value>\w+)'/)
	db_credentials = Hash.new

	mapping = {"login" => "username", "database" => "dbname"}
	row_credentials.each do |key,value|
		credential_key = mapping[key].nil? ? key : mapping[key]
		db_credentials[credential_key] = value
	end

	db_credentials
end
#########
# Based on the following resources
# 	- https://github.com/cakephp/cakepackages/blob/master/Config/deploy.rb
# 	- http://mark-story.com/posts/view/deploying-a-cakephp-site-with-capistrano
#   - https://github.com/jadb/capcake/blob/master/lib/capcake.rb
#   - http://www.assembla.com/code/cakephp_svn/subversion/nodes/trunk/deploy/deploy.rb?affiliate=d1rk
namespace :cake do

	task :setup, :roles => :web, :except => { :no_release => true } do
		if app_shared_dirs
				app_shared_dirs.each { |link| run "#{try_sudo} mkdir -p #{shared_path}#{link} && chmod 777 #{shared_path}#{link}"}
		end
		if app_symlinks
				app_symlinks.each { |link| run "#{try_sudo} mkdir -p #{shared_path}#{link} && chmod 777 #{shared_path}#{link}"}
		end
		if app_shared_files
				app_shared_files.each { |link| run "#{try_sudo} touch #{shared_path}#{link} && chmod 777 #{shared_path}#{link}" }
		end

		create_db_config
		clear_cache
		chmod
	end

	desc 'Generate / Replace the database.php file'
	task :create_db_config do
		require 'erb'
		on_rollback { run "rm #{shared_path}/Config/database.php" }

		puts "Database configuration"
		_cset :db_driver, defaults(Capistrano::CLI.ui.ask("driver [Database/Mysql]:"), 'Database/Mysql')
		_cset :db_host, defaults(Capistrano::CLI.ui.ask("hostname [localhost]:"), 'localhost')
		_cset :db_name, defaults(Capistrano::CLI.ui.ask("db name [#{application}]:"), application)
		_cset :db_login, defaults(Capistrano::CLI.ui.ask("username [#{user}]:"), user)
		_cset :db_password, Capistrano::CLI.password_prompt("password:")
		_cset :db_prefix, Capistrano::CLI.ui.ask("prefix:")
		_cset :db_persistent, defaults(Capistrano::CLI.ui.ask("persistent [false]:"), 'false')
		_cset :db_encoding, defaults(Capistrano::CLI.ui.ask("encoding [utf8]:"), 'utf8')

		DATABASE_CONFIG_TPL = <<-TEXT
<?php
class DATABASE_CONFIG {

		public $default = array(
			 'datasource' => '<%= db_driver %>',
			 'persistent' => '<%= db_persistent %>',
			 'host' => '<%= db_host %>',
			 'login' => '<%= db_login %>',
			 'password' => '<%= db_password %>',
			 'database' => '<%= db_name %>',
			 'prefix' => '<%= db_prefix %>',
			 'encoding' => '<%= db_encoding %>',
		);
}
?>
TEXT
		DATABASE_CONFIG = ERB.new(DATABASE_CONFIG_TPL).result(binding)
		put DATABASE_CONFIG, "#{shared_path}/Config/database.php", :mode => 0644
	end

	desc <<-DESC
		Force CakePHP installation to checkout a new branch/tag
		If no remote cache exists the repository will be cloned

		By default, it will checkout the :cake_branch you set in
		deploy.rb, but you can change that on runtime by specifying
		the BRANCH environment variable:

			$ cap cake:update BRANCH="1.3"

	DESC
	task :update do
		set :cake_branch, ENV['BRANCH'] if ENV.has_key?('BRANCH')

		# Clone if the repository does not exists
		run "if [ ! -d #{shared_path}/cake ]; then cd #{shared_path} && rm -rf cake && git clone --depth 1 #{cake_repo} cake; fi"

		stream "cd #{shared_path}/cake && git fetch && git checkout #{cake_branch} && git pull"
		run "#{try_sudo} rm -rf #{releases_path}/lib"
	end

	desc <<-DESC
			Touches up the released code. This is called by update_code after the basic deploy finishes.

			Any directories deployed from the SCM are first removed and then replaced with
			symlinks to the same directories within the shared location.
	DESC
	task :finalize_update, :roles => :web, :except => { :no_release => true } do
			run "chmod -R g+w #{latest_release}#{app_path}" if fetch(:group_writable, true)

			if app_symlinks
					app_symlinks.each { |link| run "#{try_sudo} rm -rf #{latest_release}#{app_path}#{link}" }
					app_symlinks.each { |link| run "ln -nfs #{shared_path}#{link} #{latest_release}#{app_path}#{link}" }
			end

			if app_shared_files
					app_shared_files.each { |link| run "#{try_sudo} rm -rf #{latest_release}#{app_path}/#{link}" }
					app_shared_files.each { |link| run "ln -s #{shared_path}#{link} #{latest_release}#{app_path}#{link}" }
			end

			sed_command = "sed -i '2idefine(\"CAKE_CORE_INCLUDE_PATH\",  \"#{shared_path}/cake/lib\");' #{latest_release}#{app_path}/webroot/index.php"
			run "if [ -d #{shared_path}/cake ]; then #{sed_command}; fi"
	end

	desc 'Blow up all the cache files CakePHP uses, ensuring a clean restart.'
	task :clear_cache do
		# Create TMP folders
		run [
			"find #{shared_path}/tmp/* -type d ! -name 'logs' -print0 | xargs -0 rm -rf",

			"mkdir -p #{shared_path}/tmp/cache/models",
			"mkdir -p #{shared_path}/tmp/cache/persistent",
			"mkdir -p #{shared_path}/tmp/cache/views",
			"mkdir -p #{shared_path}/tmp/sessions",
			"mkdir -p #{shared_path}/tmp/tests",
		].join(' && ')

		chmod
	end

	desc 'Chmod Cake directories'
	task :chmod do
		run [
			"chmod -R 777 #{shared_path}/tmp"
		].join(' && ')
	end

	## Miscellaneous tasks
	namespace :misc do
		desc 'Initialize the submodules and update them'
		task :submodule do
			run "cd #{current_release} && git submodule sync && git submodule init && git submodule update --recursive"
		end

		desc 'Remove the test file'
		task :rm_test do
			run "cd #{current_release}#{app_path} && rm -rf webroot/test.php" if deploy_env == :production
		end

		desc 'Tail the log files'
		task :tail do
			run "tail -f #{shared_path}/tmp/logs/*.log"
		end
	end

	desc <<-DESC
		Executes a cake shell on the remote server.
		Usage:
			cap cake:shell (lists all the available shells)
			cap cake:shell -s command="i18n extract" (run the "extract" method of the shell "i18n")
	DESC
	task :shell do
		command = variables[:command] || ""
		run "#{deploy_to}/#{current_dir}#{cake_binary} -app #{latest_release}#{app_path} #{command}"
	end

	## Tasks involving migrations
	namespace :migrate do
		desc 'Run CakeDC Migrations'
		task :all, :roles => :db, :only => { :primary => true } do
			run "cd #{deploy_to}/#{current_dir}"
			cake_migrations.each do |plugin|
				if plugin == "app"
					run "#{deploy_to}/#{current_dir}#{cake_binary} -app #{deploy_to}/#{current_dir}#{app_path} Migrations.migration run all"
				else
					run "#{deploy_to}/#{current_dir}#{cake_binary} -app #{deploy_to}/#{current_dir}#{app_path} Migrations.migration run all --plugin #{plugin}"
				end
			end
		end

		desc 'Gets the status of CakeDC Migrations'
		task :status, :roles => :db, :only => { :primary => true } do
			run "cd #{deploy_to}/#{current_dir} && #{deploy_to}/#{current_dir}#{cake_binary} -app #{deploy_to}/#{current_dir}#{app_path} Migrations.migration status"
		end

		# TODO Implement a revert method
	end

	## Composer related installation
	# inspired from capyfony / symfony.composer (@see https://github.com/everzet/capifony/blob/master/lib/symfony2/symfony.rb)
	# TODO Extracts "'true' == capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip" in a remote_file_exists? method
	namespace :composer do

		desc "Ensure the latest Composer version is available - Gets composer and installs it or just update"
		task :get, :roles => :app, :except => { :no_release => true } do
			if 'true' == capture("if [ -e #{previous_release}/composer.phar ]; then echo 'true'; fi").strip
				run "#{try_sudo} sh -c 'cp #{previous_release}/composer.phar #{latest_release}/'"
			end

			if 'true' == capture("if [ -e #{latest_release}/composer.phar ]; then echo 'true'; fi").strip
				run "#{try_sudo} sh -c 'cd #{latest_release} && #{php_bin} composer.phar self-update'"
			else
				run "#{try_sudo} sh -c 'cd #{latest_release} && curl -s http://getcomposer.org/installer | #{php_bin}'"
			end
		end

		desc "Runs composer to install vendors from composer.lock file"
		task :install, :roles => :app, :except => { :no_release => true } do
			if !composer_bin
				cake.composer.get
				set :composer_bin, "#{php_bin} composer.phar"
			end

			run "#{try_sudo} sh -c 'cd #{latest_release} && #{composer_bin} install #{composer_options}'"
		end

		desc "Copying vendors from previous release"
		task :copy_vendors, :except => { :no_release => true } do
			run "vendorDir=#{current_path}/Vendor; if [ -d $vendorDir ] || [ -h $vendorDir ]; then cp -a $vendorDir #{latest_release}; fi;"
		end
	end

end

after   'deploy:setup', 'cake:setup'
after   'deploy:finalize_update', 'cake:finalize_update'

# Uncomment or add this in your deploy.rb to use a Git install of CakePHP
# leave this line commented if you manage your Cake installation yourself (using composer for instance)
# before  'deploy:finalize_update', 'cake:update'
