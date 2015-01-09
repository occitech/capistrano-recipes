require 'nokogiri'

def get_database_credentials_for_magento
  config_xml_file = Nokogiri::XML(File.open("#{current_release}#{app_path}/app/etc/local.xml"))
  db_credentials = Hash.new
  ["host", "username", "password", "dbname"].each do |credential|
    db_credentials[credential] = config_xml_file.xpath("//config//global//resources//default_setup//#{credential}/text()").text
  end
  db_credentials
end

def get_database_credentials_for_cakephp
  config_file = File.open("#{current_release}#{app_path}/Config/database.php").read

  row_credentials= config_file.scan(/'(?<key>\w+)'\s=>\s'(?<value>\w+)'/)
  db_credentials = Hash.new

  mapping = {"login" => "username", "database" => "dbname"}
  row_credentials.each do |key,value|
    credential_key = mapping[key].nil? ? key : mapping[key]
    db_credentials[credential_key] = value
  end

  db_credentials
end

def is_cakephp_project
  exists?(:cake_migrations)
end

namespace :database do

  desc <<-DESC
		Generate a backup for database project.
  DESC
  task :backup, :roles => :db, :only => { :primary => true } do
    filename = "#{application}.dump.sql.gz"
    file = "/tmp/#{filename}"
    on_rollback { delete file }

    logger.info("Fetching database credentials from project")
    db_credentials = is_cakephp_project ? get_database_credentials_for_cakephp : get_database_credentials_for_magento

    logger.info("Dumping database")
    if db_credentials.length > 0
      run "mysqldump  --add-drop-table --extended-insert --force -u #{db_credentials["username"]} --password=#{db_credentials["password"]} #{db_credentials["dbname"]} -h #{db_credentials["host"]} | gzip > #{file}"  do |ch, stream, data|
        puts data
      end

      get file, "#{current_release}#{app_path}/#{filename}"
      File.delete(file)
    else
      logger.important("Unsupported type of project - No backup will be provided")
    end
  end

  desc <<-DESC
		Revert a database thanks to database backup
  DESC
  task :revert do
    logger.info("Fetching database credentials from project")
    db_credentials = is_cakephp_project ? get_database_credentials_for_cakephp : get_database_credentials_for_magento

    database_dump = "#{previous_release}#{app_path}/#{application}.dump.sql.gz"

    if File.exist?(database_dump)
      run "zcat #{database_dump} | mysql -u #{db_credentials["username"]} --password=#{db_credentials["password"]} #{db_credentials["dbname"]} -h #{db_credentials["host"]}"
    else
      logger.important("No database backup found")
    end
  end

end

before "deploy:rollback:cleanup", "database:revert"
before "deploy", "database:backup"