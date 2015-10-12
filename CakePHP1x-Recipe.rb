##
# CakePHP deployment recipe
#		TODO Implement a way to revert migrations given the map.php files of a previous release
#		TODO Make a difference between tmp files and others
#		TODO Give a way to the application to define its own custom directories
##
_cset (:app_symlinks) { [
	"/webroot/cache_css", "/webroot/cache_js",
	"/tmp"
] }
_cset(:app_shared_dirs) { ["/config", "/tmp/cache/models", "/tmp/cache/persistent", "/tmp/sessions", "/tmp/logs", "/tmp/tests"] }
_cset(:app_shared_files) { ["/config/database.php"] }

_cset(:cake_repo) { "git://github.com/cakephp/cakephp.git" }
_cset(:cake_branch) { "" }
_cset(:cake_migrations) { ['app'] }

# Used by the interactive database creation prompt
def defaults(val, default)
	val = default if (val.empty?)
	val
end

def get_database_credentials
	config_file = capture "cat #{current_release}#{app_path}/config/database.php"

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
#		- https://github.com/cakephp/cakepackages/blob/master/Config/deploy.rb
#		- http://mark-story.com/posts/view/deploying-a-cakephp-site-with-capistrano
#   - https://github.com/jadb/capcake/blob/master/lib/capcake.rb
#   - http://www.assembla.com/code/cakephp_svn/subversion/nodes/trunk/deploy/deploy.rb?affiliate=d1rk
namespace :cake do

	desc <<-DESC
			Prepares one or more servers for deployment of CakePHP.

			By default, it will create a shallow clone of the CakePHP repository
			inside shared_path/cake and run cake:update.
			It will also create needed directories

			It is safe to run this task on servers that have already been set up; it
			will not destroy any deployed revisions or data.
	DESC
	task :setup, :roles => :web, :except => { :no_release => true } do
		run "cd #{shared_path} && rm -rf cake && git clone --depth 1 #{cake_repo} cake"

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
    on_rollback { run "rm #{shared_path}/config/database.php" }

		puts "Database configuration"
		_cset :db_driver, defaults(Capistrano::CLI.ui.ask("driver [mysql]:"), 'mysql')
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
			 'driver' => '<%= db_driver %>',
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
    put DATABASE_CONFIG, "#{shared_path}/config/database.php", :mode => 0644
  end

	desc <<-DESC
		Force CakePHP installation to checkout a new branch/tag and update the symlink

		By default, it will checkout the :cake_branch you set in
		deploy.rb, but you can change that on runtime by specifying
		the BRANCH environment variable:

			$ cap cake:update BRANCH="1.3"

	DESC
	task :update do
		set :cake_branch, ENV['BRANCH'] if ENV.has_key?('BRANCH')
		stream "cd #{shared_path}/cake && git checkout #{cake_branch}"

		run "#{try_sudo} rm -rf #{latest_release}/cake  && ln -nfs #{shared_path}/cake/cake #{latest_release}/cake"
	end

	desc <<-DESC
			Touches up the released code. This is called by update_code after the basic deploy finishes.

			Any directories deployed from the SCM are first removed and then replaced with
			symlinks to the same directories within the shared location.
	DESC
	task :finalize_update, :roles => :web, :except => { :no_release => true } do
			run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)

			if app_symlinks
					app_symlinks.each { |link| run "#{try_sudo} rm -rf #{latest_release}#{link}" }
					app_symlinks.each { |link| run "ln -nfs #{shared_path}#{link} #{latest_release}#{link}" }
			end

			if app_shared_files
					app_shared_files.each { |link| run "#{try_sudo} rm -rf #{latest_release}/#{link}" }
					app_shared_files.each { |link| run "ln -s #{shared_path}#{link} #{latest_release}#{link}" }
			end

	end

	desc 'Blow up all the cache files CakePHP uses, ensuring a clean restart.'
	task :clear_cache do
		# Create TMP folders
		run [
			"find #{shared_path}/tmp/* -type d ! -name 'logs' -print0 | xargs -0 rm -rf",
			"rm -rf #{shared_path}/webroot/cache_css/*",
			"rm -rf #{shared_path}/webroot/cache_js/*",

			"mkdir -p #{shared_path}/tmp/cache/models",
			"mkdir -p #{shared_path}/tmp/cache/persistent",
			"mkdir -p #{shared_path}/tmp/cache/views",
			"mkdir -p #{shared_path}/tmp/sessions",
			"mkdir -p #{shared_path}/tmp/logs",
			"mkdir -p #{shared_path}/tmp/tests",
		].join(' && ')

		chmod
	end

	desc 'Chmod Cake directories'
	task :chmod do
		run [
			"chmod -R 777 #{shared_path}/tmp #{shared_path}/webroot/cache_css #{shared_path}/webroot/cache_js",
			# Add here upload directories and other app-specif files
		].join(' && ')
	end

	## Miscellaneous tasks
	namespace :misc do
		desc 'Initialize the submodules and update them'
		task :submodule do
			run "cd #{current_release} && git submodule init && git submodule update"
		end

		desc 'Remove the test file'
		task :rm_test do
			run "cd #{current_release} && rm -rf webroot/test.php" if deploy_env == :production
		end

		desc 'Tail the log files'
		task :tail do
			run "tail -f #{shared_path}/tmp/logs/*.log"
		end
	end

	## Tasks involving migrations
	namespace :migrate do
		desc 'Run CakeDC Migrations'
		task :all, :roles => :db, :only => { :primary => true } do
			run "cd #{deploy_to}/#{current_dir}"
			cake_migrations.each do |plugin|
				if plugin == "app"
					run "#{shared_path}/cake/cake/console/cake -app #{deploy_to}/#{current_dir} migration all"
				else
					run "#{shared_path}/cake/cake/console/cake -app #{deploy_to}/#{current_dir} migration all -plugin #{plugin}"
				end
			end
		end

		desc 'Gets the status of CakeDC Migrations'
		task :status, :roles => :db, :only => { :primary => true } do
			run "cd #{deploy_to}/#{current_dir} && #{shared_path}/cake/cake/console/cake -app #{deploy_to}/#{current_dir} migration status"
		end

		# TODO Implement a revert method
	end

end

after   'deploy:setup', 'cake:setup'
before  'deploy:finalize_update', 'cake:update'
after   'deploy:finalize_update', 'cake:finalize_update'
