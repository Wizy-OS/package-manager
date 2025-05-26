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
    puts "Removing #{pkg}"
    remove(pkg)
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
    output = db.scalar "SELECT is_installed FROM packages WHERE name='#{str}'"
  rescue
    STDERR.puts "#{str} does not exist in local_index.sqlite3"
  ensure
    result = true if output == 1
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
    db.query "SELECT name FROM packages WHERE is_installed=1" do |res|
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
        puts "UPDATE packages SET is_installed=1 WHERE name='#{pkg_name}'"
        db.exec "UPDATE packages SET is_installed=1 WHERE name='#{pkg_name}'"
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
    STDERR.puts "Error: #{pkg_name} is not available in database"
    exit -1
  end

  if pkg_installed?(pkg_name)
    puts "#{pkg_name} is already installed."
    return 0
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

  # handle dependecies
  dep_list = [] of String
  DB.open db_file do |db|
    id = get_pkg_id(pkg_name)
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
    db.exec "UPDATE packages SET is_installed=1 WHERE name='#{pkg_name}'"
  end

  # extract package to file system
  # process = Process.new("bsdtar -xvf #{cache_file} -C #{Globals.root}")
  proc = Process.new("bsdtar", ["-xvf", cache_file, "-C", Globals.root,
                                "--exclude", "^props.yml",
                                "--exclude", "^files",
                                "--exclude", "^dirs",
                                "--exclude", "^install"],
                                output: Process::Redirect::Pipe)
  proc.wait
end

def get_pkg_id(pkg_name : String)
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
  pkg_id = nil
  DB.open db_file do |db|
    pkg_id = db.scalar "SELECT pkgId FROM packages WHERE name='#{pkg_name}'"
  end
  pkg_id
end

def get_pkg_name(pkg_id : Int64)
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
  pkg_name = nil
  DB.open db_file do |db|
    pkg_name = db.scalar "SELECT name FROM packages WHERE pkgId='#{pkg_id}'"
  end
  pkg_name
end

def remove(pkg_name : String)
  unless pkg_installed?(pkg_name)
    puts "#{pkg_name} is not installed."
    return
  end

  puts "#{pkg_name} found as installed"

  # TODO check if some other package depend on this package
  # 1. if this package don't exist in dependencies table,
  #    then some other package do not depends on it
  # 2. Print some other package(s)
  # 3. exit
  dependent_ids = [] of Int64
  db_file = "sqlite3://#{Globals.local_db_path}/local_index.sqlite3"
  DB.open db_file do |db|
    db.query "SELECT pkgId FROM dependencies WHERE depName='#{pkg_name}'" \
      do |result|
      result.each do
        dep_id = result.read(Int64)
        dependent_ids.push(dep_id)
      end
    end
  end

  puts dependent_ids
  dependants_names = dependent_ids.map do |i|
    get_pkg_name(i)
  end

  installed_pkgs = [] of String
  dependants_names.each do |x|
    if pkg_installed?(x.as(String))
      installed_pkgs.push(x.as(String))
    end
  end

  unless installed_pkgs.empty?
    puts "reverse dependencies found for #{pkg_name}:" unless dependent_ids.empty?
    dependent_ids.each do |dep_id|
      dep_name = get_pkg_name(dep_id)
      puts "\t#{dep_name}"
    end

    unless dependent_ids.empty?
      STDERR.puts "First remove dependent packages for #{pkg_name}"
      STDERR.puts "Aborting process."
      exit -1
    end
  end

  # Mark package as not installed
  DB.open db_file do |db|
    db.exec "UPDATE packages SET is_installed=0 WHERE name='#{pkg_name}'"
  end

  # Delete files from file system carefully
  id = get_pkg_id(pkg_name)
  pkg_files = [] of String
  DB.open db_file do |db|
    db.query "SELECT path FROM files WHERE pkgId=#{id}" \
      do |result|
      result.each do
        file = result.read(String)
        pkg_files.push(file)
      end
    end
  end

  pkg_files = pkg_files.map { |f| "#{Globals.root}/#{f}"}
  pkg_files.each do |path|
    puts "removing #{path}"
    dir = File.directory?(path)
    if dir
      if path.empty?
        Dir.delete(path)
      end
    else
      begin
        File.delete(path)
      rescue ex
        puts "WARNING: #{path}, does not exist, owned by #{pkg_name}"
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

