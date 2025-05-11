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
  parser.on "-L", "List all packages from repo" do
    puts "Syncing repos"
    repo_list
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
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
  result = false
  DB.open db_file do |db|
    count = db.scalar "SELECT count(name) FROM packages WHERE name='#{str}'"
    result = true if count == 1
  end
  result
end

def pkg_installed?(str : String)
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
  result = false
  DB.open db_file do |db|
    res = db.scalar "SELECT is_installed FROM packages WHERE name='#{str}'"
    result = true if res == true
  end
  result
end

def db_migration
  puts "Running DB migration"
  remote_index = "#{Globals.local_db_path}/remote_index.sqlite3"
  local_index = "#{Globals.local_db_path}/local_index.sqlite3"

  pkg_names = [] of String

  unless File.exists?(local_index)
    puts "No migrations to run"
    return
  end

  # Case: when some packages are installed
  DB.open "sqlite3://#{local_index}" do |db|
    # 1 = True, 0 = False
    db.query "SELECT name FROM packages WHERE is_installed=TRUE" do |res|
      res.each do
        name = res.read(String)
        pkg_names.push(name)
      end
    end
  end

  puts pkg_names
  File.copy(remote_index, local_index)
  unless pkg_names.empty?
    DB.open "sqlite3://#{local_index}" do |db|
      pkg_names.each do |pkg_name|
        db.exec "UPDATE packages SET is_installed=1 \
          WHERE name="#{pkg_name}""
      end
    end
  end

end

def fetch_db
  # fetch from Remote todo
  index_db = "#{Globals.remote_db_path}/index.sqlite3"
  our_remote_db = "#{Globals.local_db_path}/remote_index.sqlite3"
  File.copy(index_db, our_remote_db)

  our_local_db = "#{Globals.local_db_path}/local_index.sqlite3"
  unless File.exists?(our_local_db)
    File.copy(our_remote_db, our_local_db)
  end
  db_migration
end

def repo_list
  puts Globals.local_db_path
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
  DB.open db_file do |db|
    db.query "SELECT name,version,description,is_installed \
    FROM packages" do |result|
      result.each do
        name = result.read(String)
        ver = result.read(String)
        desc = result.read(String)
        is_installed = result.read(Int)

        puts "#{name}\t #{ver}\t #{"i" if is_installed == 1}\t #{desc}"
      end
    end
  end
end

def search(str : String)
  puts Globals.local_db_path
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
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

def install(pkg_name : String)
  unless pkg_exist?(pkg_name)
    puts "#{pkg_name} is not available in database"
    return
  end

  if pkg_installed?(pkg_name)
    puts "#{pkg_name} is already installed."
    return
  end

  # construct filename from db
  file_name = ""
  db_file = "sqlite3://#{Globals.local_db_path}/remote_index.sqlite3"
  DB.open db_file do |db|
    db.query "SELECT name,version FROM packages WHERE name='#{pkg_name}'" \
      do |result|
      result.each do
        name = result.read(String)
        ver = result.read(String).sub("-","_")

        file_name = "#{name}-#{ver}.wpkg.tar.zstd"
      end
    end
  end

  # copy file to cache to mark as installed
  remote_file = "#{Globals.remote_db_path}/#{file_name}"
  cache_file = "#{Globals.cache}/#{file_name}"
  File.copy(remote_file, cache_file)

  # TODO handle dependecies
  dep_list = [] of String
  DB.open db_file do |db|
    id = db.scalar "SELECT pkgId FROM packages WHERE name='#{pkg_name}'"
    puts "id = #{id}"
    db.query "SELECT depName from dependencies WHERE pkgId=#{id}" do |res|
      res.each do
        dep_list.push(res.read(String))
      end
    end
  end

  puts dep_list
  dep_list.each do |pkg|
    install(pkg)
  end

  # mark as installed in DB
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
  DB.open db_file do |db|
    db.exec "UPDATE packages SET is_installed=TRUE WHERE name='#{pkg_name}'"
  end

  # extract package to file system
  # process = Process.new("bsdtar -xvf #{cache_file} -C #{Globals.root}")
  proc = Process.new("bsdtar", ["-xvf", cache_file, "-C", Globals.root,
                                "--exclude", "props.yml",
                                "--exclude", "files",
                                "--exclude", "dirs",
                                "--exclude", "install"],
                                output: Process::Redirect::Pipe)
  proc.wait

end

unless OPTIONS[:search].empty?
  search(OPTIONS[:search])
end
unless OPTIONS[:info].empty?
  puts pkg_exist?(OPTIONS[:info])
end

