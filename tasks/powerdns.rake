# Inspired by powerdns, which was inspired by rabbitmq.rake the Redbox project at http://github.com/rick/redbox/tree/master
require 'rake'
require 'fileutils'
require 'pathname'
require 'sys/uname'

class PDNS
  SOURCE_URI  = "http://downloads.powerdns.com/releases/pdns-2.9.22.tar.gz"
  BOOST_URI   = "http://downloads.sourceforge.net/project/boost/boost/1.42.0/boost_1_42_0.tar.gz?use_mirror=superb-sea2"
  DTACH_URI   = "http://downloads.sourceforge.net/project/dtach/dtach/0.8/dtach-0.8.tar.gz"
  ROOT        = (Pathname.new(File.dirname(__FILE__)) + '../powerdns').cleanpath
  PDNS_SERVER = 'pdns_server'
  BACKEND     = 'backend'

  def self.bin() ROOT + 'bin' end
  def self.etc() ROOT + 'etc' end
  def self.src() ROOT + 'src' end
  def self.tmp() ROOT + 'tmp' end

  def self.source_path()    src + 'powerdns' end
  def self.compiled_path()  source_path + 'pdns' end
  def self.boost_path()     src + 'boost' end

  def self.server_command() bin + PDNS_SERVER end
  def self.pipe_command()   bin + BACKEND end
  def self.config()         etc + 'pdns.conf' end

  def self.dtach_socket
    tmp.mkpath
    tmp + 'powerdns.dtach'
  end

  # Just check for existance of dtach socket
  def self.running?
    File.exists? dtach_socket
  end

  def self.start
    puts 'Detach with Ctrl+\  Re-attach with rake powerdns:attach'
    sleep 3
    exec "dtach -A #{dtach_socket} #{server_command}"
  end

  def self.start_detached
    system "dtach -n #{dtach_socket} #{server_command}"
  end

  def self.attach
    exec "dtach -a #{dtach_socket}"
  end

  def self.stop
    system 'echo "SHUTDOWN" | nc localhost 6379'
  end

end

namespace :powerdns do

  desc 'About powerdns'
  task :about do
    puts "\nSee http://www.powerdns.com/ for information about PowerDNS.\n\n"
  end

  desc 'Start powerdns'
  task :start do
    PDNS.start
  end

  desc 'Stop powerdns'
  task :stop do
    PDNS.stop
  end

  desc 'Restart powerdns'
  task :restart do
    PDNS.stop
    PDNS.start
  end

  desc 'Attach to powerdns dtach socket'
  task :attach do
    PDNS.attach
  end

  desc 'Install PowerDNS server and configuration file'
  task :install => %w[about install:server install:backend install:config]

  namespace :install do
    desc 'Install PowerDNS server'
    task :server => [:paths] do
      script = PDNS.server_command
      script.delete if script.exist?
      script.open('w') do |f|
        f.puts <<-SCRIPT
#!/bin/bash
sudo #{PDNS.compiled_path.realpath + PDNS::PDNS_SERVER} --config-dir=#{PDNS.etc}
        SCRIPT
      end
      script.chmod(0755)
      puts "Installed #{script}."
    end

    desc 'Install PowerDNS config'
    task :config => [:backend, :paths] do
      config = PDNS.config
      config.delete if config.exist?
      config.open('w') do |file|
        file.puts <<-CONFIG
launch=pipe
pipe-command=#{PDNS.pipe_command}
pipebackend-abi-version=2
        CONFIG
      end
      `cat #{PDNS.compiled_path.realpath + 'pdns.conf-dist'} >> #{config}`
      puts "Installed #{config} and configured it for testing.\n You should double check this file."
    end

    desc 'Install backend wrapper'
    task :backend => [:paths] do
      executable = File.expand_path('../..', __FILE__)
      pipe = PDNS.pipe_command
      pipe.delete if pipe.exist?
      pipe.open('w') do |f|
        f.puts <<-SCRIPT
#!/bin/bash
cd #{executable}
bundle exec bin/backend
        SCRIPT
      end
      pipe.chmod(0755)
      puts "Linked #{pipe} to #{executable}."
    end
  end

  desc "Configure and make PowerDNS"
  task :make => [:paths, :download, :boost] do
    cflags = "-I#{PDNS.boost_path.realpath}"
    cflags << " -DDARWIN" if Sys::Uname.sysname =~ /Darwin/i

    system <<-COMMAND
cd #{PDNS.source_path}

echo "Configuring PowerDNS for pipe backend ..."
CXXFLAGS="#{cflags}" ./configure --with-modules=pipe --without-pgsql --without-mysql --without-sqlite --without-sqlite3

echo "make clean ..."
make clean

echo "make ..."
make
    COMMAND
  end

  desc "Download PowerDNS source"
  task :download => [:paths, :boost] do
    source_path = PDNS.source_path
    unless source_path.exist?
      source_path.mkpath
      puts "Downloading PowerDNS source..."
      system "curl -L #{PDNS::SOURCE_URI} | tar zx --strip-components 1 -C #{source_path}"
    end
  end

  desc "PowerDNS requires boost libs at compile time"
  task :boost => :paths do
    boost_path = PDNS.boost_path
    unless boost_path.exist?
      boost_path.mkpath
      puts "Downloading Boost source..."
      system "curl -L #{PDNS::BOOST_URI} | tar zx --strip-components 1 -C #{boost_path}"
    end
  end

  task :paths do
    [PDNS.bin, PDNS.etc, PDNS.src].each { |path| path.mkpath }
  end

  namespace :purge do
    def purge(*paths)
      paths.each do |path|
        path.rmtree if path.exist?
        path.mkpath
      end
    end

    task :installs do
      purge(PDNS.bin, PDNS.etc)
    end
    
    task :src do
      purge(PDNS.src)
    end
  end
end

namespace :dtach do
  desc 'About dtach'
  task :about do
    puts <<-ABOUT
dtach allows background proccess that are not attached to a term.
See http://dtach.sourceforge.net/ for more information about dtach.

ABOUT
  end

  desc 'Install dtach 0.8 from source'
  task :install => [:about] do
    dtach_path = PDNS.source_path + 'dtach'

    unless dtach.exist?
      dtach.mkpath
      system "curl -L #{PDNS::DTACH_URI} | tar zx --strip-components 1 -C #{dtach_path}"
    end

    system "cd #{dtach_path} && ./configure && make && ln -s dtach #{PDNS.bin + 'dtach'}"
    puts "dtach installed to #{PDNS.bin}."
  end
end
