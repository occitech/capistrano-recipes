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
    run "mysqldump  --add-drop-table --extended-insert --force -u #{db_credentials["username"]} --password=#{db_credentials["password"]} #{db_credentials["dbname"]} -h #{db_credentials["host"]} | gzip > #{file}"  do |ch, stream, data|
      puts data
    end

    get file, "#{current_release}#{app_path}/#{filename}"
    File.delete(file)
  end

  desc <<-DESC
		Revert a database thanks to database backup
  DESC
  task :revert do
    database_dump = "#{previous_release}#{app_path}/#{application}.dump.sql.gz"

    unless File.exist?(database_dump)
      raise("No database backup found")
    end
    unless exists?(:db_credentials)
      raise("Cannot access database for #{application}")
    end
    run "zcat #{database_dump} | mysql -u #{db_credentials["username"]} --password=#{db_credentials["password"]} #{db_credentials["dbname"]} -h #{db_credentials["host"]}"
  end

end

before "deploy:rollback:cleanup", "database:revert"
before "deploy", "database:backup"