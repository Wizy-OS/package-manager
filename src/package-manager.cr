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
    raise "TODO: Implement"
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
    puts "Setting #{path}"
    Globals.set_root_path(path)
  end
  parser.on "-I <REPOPATH>", "Specify Repo path" do |path|
    puts "Setting repo #{path}"
    Globals.set_db_path(path)
  end
end

class Globals
  @@db_path = "/var/cache/wpkg"
  @@root = "/"

  def self.db_path
    @@db_path
  end

  def self.set_db_path(path : String)
    @@db_path = File.expand_path(path)
  end

  def self.db
    "#{@@db_path}/index.sqlite3"
  end

  def self.set_root_path(path : String)
    @@root = File.expand_path(path)
  end

  def self.root
    @@root
  end
end

def pkg_exist?(str : String)
  db_file = "sqlite3://#{Globals.db}"
  result = false
  DB.open db_file do |db|
    count = db.scalar "SELECT count(name) FROM packages WHERE name='#{str}'"
    result = true if count == 1
  end
  result
end

def search(str : String)
  puts Globals.db
  db_file = "sqlite3://#{Globals.db}"
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


unless OPTIONS[:search].empty?
  search(OPTIONS[:search])
end
unless OPTIONS[:info].empty?
  puts pkg_exist?(OPTIONS[:info])
end

