require "option_parser"
require "db"
require "sqlite3"

OPTIONS = {
  :search => "",
  :info => "",
}

option_parser = OptionParser.parse do |parser|
  parser.banner = "Welcome to WizOS Package manager"

  parser.on "-v", "Show version" do
    puts "version 1.0"
    exit
  end
  parser.on "-h", "Show help" do
    puts parser
    exit
  end
  parser.on "-i PKG", "Install package" do |pkg|
    puts "Installing #{pkg}"
    install(pkg)
  end
  parser.on "-s PKG", "Search package" do |str|
    puts "Searching #{str}"
    OPTIONS[:search] = str
  end
  parser.on "-r PKG", "Remove package" do |pkg|
    puts "Installing #{pkg}"
    raise "TODO: Implement"
  end
  parser.on "-V PKG", "Display package details" do |pkg|
    puts "Info #{pkg}"
    OPTIONS[:info] = pkg
  end
  parser.on "-R ROOT", "Specify Root directory for installation" do |path|
    puts "Setting root #{path}"
    Globals.set_root_path(path)
  end
  parser.on "-I <REPOPATH>", "Specify remote Repo path" do |path|
    puts "Setting repo #{path}"
    Globals.add_remote_db_path(path)
  end
  parser.on "-S", "Sync repositories" do
    puts "Syncing repos"
    fetch_db
  end
end

class Globals
  @@cache = "#{@@root}/var/cache/wpkg"
  @@local_db_path = "#{@@root}/var/db/wpkg"
  @@remote_db_path = ""
  @@root = "/"

  def self.local_db_path
    @@local_db_path
  end

  def self.add_remote_db_path(path : String)
    @@remote_db_path = File.expand_path(path)
  end

  def self.remote_db_path
    "#{@@remote_db_path}"
  end

  def self.set_root_path(path : String)
    @@root = File.expand_path(path)
  end

  def self.root
    @@root
  end

  def self.cache
    @@cache
  end
end

def pkg_exist?(str : String)
  db_file = "sqlite3://#{Globals.local_db_path}/index.sqlite3"
  result = false
  DB.open db_file do |db|
    count = db.scalar "SELECT count(name) FROM packages WHERE name='#{str}'"
    result = true if count == 1
  end
  result
end

def fetch_db
  # fetch from Remote todo

  # locally
  remote_db = "#{Globals.remote_db_path}/index.sqlite3"
  local_db = "#{Globals.local_db_path}/index.sqlite3"
  File.copy(remote_db, local_db)
end

def search(str : String)
  puts Globals.local_db_path
  db_file = "sqlite3://#{Globals.local_db_path}/index.sqlite3"
  DB.open db_file do |db|
    db.query "SELECT name,version,description FROM packages \
    WHERE name like '%#{str}%' ORDER BY name" do |result|
      result.each do
        name = result.read(String)
        ver = result.read(String)
        desc = result.read(String)

        puts "#{name}[#{ver}] \t\t #{desc}"
      end
    end
  end
end

def install(str : String)
  fetch_db

  unless pkg_exist?(str)
    puts "Error: #{str} not found"
    return
  end

  # construct filename from db
  file_name = ""
  db_file = "sqlite3://#{Globals.local_db_path}/index.sqlite3"
  DB.open db_file do |db|
    db.query "SELECT name,version FROM packages WHERE name='#{str}'" \
      do |result|
      result.each do
        name = result.read(String)
        ver = result.read(String).sub("-","_")

        file_name = "#{name}-#{ver}.wpkg.tar.zstd"
      end
    end
  end

  # copy file to cache
  remote_file = "#{Globals.remote_db_path}/#{file_name}"
  cache_file = "#{Globals.cache}/#{file_name}"
  File.copy(remote_file, cache_file)

  # TODO handle dependecies
  # TODO extract package to file system
end

unless OPTIONS[:search].empty?
  search(OPTIONS[:search])
end
unless OPTIONS[:info].empty?
  puts pkg_exist?(OPTIONS[:info])
end

