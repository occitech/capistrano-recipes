require 'mkmf'
_cset(:mysqldump_bin) { "/usr/bin/env mysqldump" }
_cset(:mysql_bin) { "/usr/bin/env mysql" }
_cset(:app_path) { "" }

# http://stackoverflow.com/questions/1661586/how-can-you-check-to-see-if-a-file-exists-on-the-remote-server-in-capistrano
def remote_file_exists?(full_path)
  'true' ==  capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip
end

namespace :database do

  desc <<-DESC
		Generate a backup for database project.
  DESC
  task :backup, :roles => :db, :only => { :primary => true } do
    filename = "#{application}.dump.sql.gz"
    file = "/tmp/#{filename}"
    on_rollback { delete file }

    unless exists?(:db_credentials)
      raise("Cannot access database for #{application}")
    end

    logger.info("Dumping database")
    run "#{mysqldump_bin} --add-drop-table --extended-insert --force -u #{db_credentials["username"]} --password='#{db_credentials["password"]}' #{db_credentials["dbname"]} -h #{db_credentials["host"]} | gzip > #{file}"  do |ch, stream, data|
      puts data
    end

    run "mv #{file} #{current_release}#{app_path}/#{filename}"
  end

  desc <<-DESC
		Revert a database thanks to database backup
  DESC
  task :revert do
    database_dump = "#{previous_release}#{app_path}/#{application}.dump.sql.gz"

    unless remote_file_exists?(database_dump)
      raise("No database backup found")
    end
    unless exists?(:db_credentials)
      raise("Cannot access database for #{application}")
    end
    run "zcat #{database_dump} | #{mysql_bin} -u #{db_credentials["username"]} --password='#{db_credentials["password"]}' #{db_credentials["dbname"]} -h #{db_credentials["host"]}"
  end

end
