require 'nokogiri'
_cset (:app_symlinks) { ["/media", "/var", "/sitemaps"] }
_cset (:app_shared_dirs) { ["/app/etc", "/sitemaps", "/media", "/var"] }
_cset (:app_shared_files) { ["/app/etc/local.xml"] }
_cset (:app_path) { "" } # Path of the Magento app from the root of the project
_cset (:copy_exclude) { [] }

set :copy_exclude, copy_exclude.concat(['/.git', '/config', '/downloader', '/.gitignore', '/.htaccess.sample'])

def get_database_credentials
    config_xml = capture "cat #{current_release}#{app_path}/app/etc/local.xml"
    config_xml_file = Nokogiri::XML(config_xml)
    db_credentials = Hash.new
    ["host", "username", "password", "dbname"].each do |credential|
        db_credentials[credential] = config_xml_file.xpath("//config//global//resources//default_setup//#{credential}/text()").text
    end
    db_credentials
end

namespace :mage do

    desc <<-DESC
        Prepares one or more servers for deployment of Magento. Before you can use any \
        of the Capistrano deployment tasks with your project, you will need to \
        make sure all of your servers have been prepared with `cap deploy:setup'. When \
        you add a new server to your cluster, you can easily run the setup task \
        on just that server by specifying the HOSTS environment variable:

            $ cap HOSTS=new.server.com mage:setup

        It is safe to run this task on servers that have already been set up; it \
        will not destroy any deployed revisions or data.
    DESC
    task :setup, :roles => :web, :except => { :no_release => true } do
        if app_shared_dirs
            app_shared_dirs.each { |link| run "#{try_sudo} mkdir -p #{shared_path}#{app_path}#{link} && #{try_sudo} chmod 777 #{shared_path}#{app_path}#{link}"}
        end
        if app_shared_files
            app_shared_files.each { |link| run "#{try_sudo} touch #{shared_path}#{app_path}#{link} && #{try_sudo} chmod 777 #{shared_path}#{app_path}#{link}" }
        end
    end

    desc <<-DESC
        Touches up the released code. This is called by update_code \
        after the basic deploy finishes.

        Any directories deployed from the SCM are first removed and then replaced with \
        symlinks to the same directories within the shared location.
    DESC
    task :finalize_update, :roles => :web, :except => { :no_release => true } do
        run "chmod -R g+w #{latest_release}#{app_path}" if fetch(:group_writable, true)

        if app_symlinks
            # Remove the contents of the shared directories if they were deployed from SCM
            app_symlinks.each { |link| run "#{try_sudo} rm -rf #{latest_release}#{app_path}#{link}" }
            # Add symlinks the directoris in the shared location
            app_symlinks.each { |link| run "ln -nfs #{shared_path}#{app_path}#{link} #{latest_release}#{app_path}#{link}" }
        end

        if app_shared_files
            # Remove the contents of the shared directories if they were deployed from SCM
            app_shared_files.each { |link| run "#{try_sudo} rm -rf #{latest_release}#{app_path}#{link}" }
            # Add symlinks the directoris in the shared location
            app_shared_files.each { |link| run "ln -s #{shared_path}#{app_path}#{link} #{latest_release}#{app_path}#{link}" }
        end
    end

    desc <<-DESC
        Clear the Magento Cache
    DESC
    task :cc, :roles => :web do
      run "cd #{current_path}#{app_path} && rm -rf var/cache/*"
    end

    desc <<-DESC
        Disable the Magento install by creating the maintenance.flag in the web root.
    DESC
    task :disable, :roles => :web do
      run "cd #{current_path}#{app_path} && touch maintenance.flag"
    end

    desc <<-DESC
        Enable the Magento stores by removing the maintenance.flag in the web root.
    DESC
    task :enable, :roles => :web do
      run "cd #{current_path}#{app_path} && rm -f maintenance.flag"
    end

    desc <<-DESC
        Run the Magento compiler
    DESC
    task :compiler, :roles => :web do
        run "cd #{current_path}#{app_path}/shell && php -f compiler.php -- compile"
    end

    desc <<-DESC
        Enable the Magento compiler
    DESC
    task :enable_compiler, :roles => :web do
        run "cd #{current_path}#{app_path}/shell && php -f compiler.php -- enable"
    end

    desc <<-DESC
        Disable the Magento compiler
    DESC
    task :disable_compiler, :roles => :web do
        run "cd #{current_path}#{app_path}/shell && php -f compiler.php -- disable"
    end

    desc <<-DESC
        Run the Magento indexer
    DESC
    task :indexer, :roles => :app do
        run "cd #{current_path}#{app_path}/shell && php -f indexer.php -- reindexall"
    end

    desc <<-DESC
        Clean the Magento logs
    DESC
    task :clean_logs, :roles => :web do
        run "cd #{current_path}#{app_path}/shell && php -f log.php -- clean"
    end

        # From https://github.com/augustash/capistrano-ash/
        desc "Watch Magento system log"
    task :watch_logs, :roles => :web, :except => { :no_release => true } do
      run "tail -f #{shared_path}#{app_path}/var/log/system.log" do |channel, stream, data|
        puts  # for an extra line break before the host name
        puts "#{channel[:host]}: #{data}"
        break if stream == :err
      end
    end

    desc "Watch Magento exception log"
    task :watch_exceptions, :roles => :web, :except => { :no_release => true } do
      run "tail -f #{shared_path}#{app_path}/var/log/exception.log" do |channel, stream, data|
        puts  # for an extra line break before the host name
        puts "#{channel[:host]}: #{data}"
        break if stream == :err
      end
    end

  desc "Lauch Magento migrations / setups"
  task :migrate, roles => :app do
    run "cd #{current_path}#{app_path}/ && php -f index.php"
  end
end

after   'deploy:setup', 'mage:setup'
after   'deploy:finalize_update', 'mage:finalize_update'
