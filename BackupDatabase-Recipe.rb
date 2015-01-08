require 'nokogiri'

def get_database_credentials_for_magento
  configXMLFile = Nokogiri::XML(File.open("#{current_release}#{app_path}/app/etc/local.xml"))
  dbCredentials = Hash.new
  ["host", "username", "password", "dbname"].each do |credential|
    dbCredentials[credential] = configXMLFile.xpath("//config//global//resources//default_setup//#{credential}/text()").text
  end
  dbCredentials
end

def get_database_credentials_for_cakephp
  configFile = File.open("#{current_release}#{app_path}/Config/database.php").read

  rowCredentials= configFile.scan(/'(?<key>\w+)'\s=>\s'(?<value>\w+)'/)
  dbCredentials = Hash.new

  mapping = {"login" => "username", "database" => "dbname"}
  rowCredentials.each do |key,value|
    credentialKey = mapping[key].nil? ? key : mapping[key]
    dbCredentials[credentialKey] = value
  end

  dbCredentials
end

def is_cakephp_project
  exists?(:cake_migrations)
end

namespace :database do

  desc <<-DESC
		Backup a database
  DESC
  task :backup, :roles => :db, :only => { :primary => true } do
    filename = "#{application}.dump.sql.gz"
    file = "/tmp/#{filename}"
    on_rollback { delete file }

    logger.info("Fetching database credentials from project")
    dbCredentials = is_cakephp_project ? get_database_credentials_for_cakephp : get_database_credentials_for_magento

    logger.info("Dumping database")
    if dbCredentials.length > 0
      run "mysqldump  --add-drop-table --extended-insert --force -u #{dbCredentials["username"]} --password=#{dbCredentials["password"]} #{dbCredentials["dbname"]} -h #{dbCredentials["host"]} | gzip > #{file}"  do |ch, stream, data|
        puts data
      end

      get file, "#{current_release}#{app_path}/#{filename}"
      File.delete(file)
    else
      logger.important("Unsupported type of project - No backup will be provided")
    end
  end

  task :revert do
    logger.info("Fetching database credentials from project")
    dbCredentials = is_cakephp_project ? get_database_credentials_for_cakephp : get_database_credentials_for_magento

    databaseDump = "#{previous_release}#{app_path}/#{application}.dump.sql.gz"

    if File.exist?(databaseDump)
      run "zcat #{databaseDump} | mysql -u #{dbCredentials["username"]} --password=#{dbCredentials["password"]} #{dbCredentials["dbname"]} -h #{dbCredentials["host"]}"
    else
      logger.important("No database backup found")
    end
  end
end

before "deploy:rollback:cleanup", "database:revert"
before "deploy", "database:backup"