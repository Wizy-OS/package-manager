require "option_parser"

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
  parser.on "-s PKG", "Search package" do |pkg|
    puts "Searching #{pkg}"
    raise "TODO: Implement"
  end
  parser.on "-r PKG", "Remove package" do |pkg|
    puts "Installing #{pkg}"
    raise "TODO: Implement"
  end
  parser.on "-R ROOT", "Specify Root directory for installation" do |path|
    puts "Setting #{path}"
    raise "TODO: Implement"
 end
end
