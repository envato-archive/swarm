module Swarm
  class Queen
    include Singleton
    include OutputHelper

    attr_reader :formatter

    SCHEMA_SANITIZATION_SED = "sed -e 's/ AUTO_INCREMENT=[0-9]*//' -e 's/--.*//'"
    MD5_CMD = RUBY_PLATFORM =~ /darwin/ ? 'md5' : 'md5sum'

    def self.rule
      instance.rule
    end

    def initialize
      load_environment
      @base_environment_name = Rails.env
      @base_environment_configuration = ActiveRecord::Base.configurations[@base_environment_name].dup
      @base_environment_db = @base_environment_configuration['database']
      @project_root = Rails.root

      load_test_times
      choose_formatter
    end

    def rule
      detect_cores
      dump_development_schema
      build_drone_deployment_config
      populate_queue

      @formatter.started
      voice.start # not sure I like calling this a 'voice'
      start_server { deploy_drones }
      at_exit { @server.close if @server }
      Process.waitall
      @formatter.completed
      save_test_times
      voice.stop
    end

    protected

    def load_test_times
      if File.exists?(Swarm.test_times_file)
        @test_times = Hash[*File.readlines(Swarm.test_times_file).map do |line|
          file, time = line.split(/::/, 2)
          [file, time.to_f]
        end.flatten]
      else
        @test_times = {}
      end
    end

    def save_test_times
      File.open(Swarm.test_times_file, 'w') do |file|
        @test_times.to_a.sort do |a, b|
          b.last <=> a.last
        end.each do |test, time|
          file << "#{test}::#{time}\n"
        end
      end
    end

    def test_time_for(file)
      @test_times[clean_test_path(file)] || 9001 # Run unknown tests first
    end

    def clean_test_path(file)
      file.gsub("#{@project_root}/", '')
    end

    def log_test_time(file, time)
      return if file =~ /\.feature$/ && time < 1 # Do not log features if they take less than a second because it means they were skipped (@series)
      @test_times[clean_test_path(file)] = time
    end

    def build_drone_deployment_config
      default_options = {:create_database => false, :reload_schema => false, :db_access_opts => db_access_opts, :project_root => @project_root}
      @drone_config = {@base_environment_db => default_options}
      (@num_drones - 1).times { |i| @drone_config["#{@base_environment_db}#{i + 1}"] = default_options }

      detect_databases_needing_create.each { |db| @drone_config[db][:create_database] = true }
      detect_databases_needing_schema_reload.each {|db| @drone_config[db][:reload_schema] = true }

      debug(@drone_config.inspect)
    end

    def detect_databases_needing_create
      existing_dbs = `echo "show databases" | mysql #{db_access_opts}`.strip.split("\n")[1..-1] # First line is column header.
      @drone_config.keys.find_all { |db| !existing_dbs.include?(db) }
    end

    def detect_databases_needing_schema_reload
      needing_schema = []
      @drone_config.each do |db, opts|
        if opts[:create_database]
          needing_schema << db
        else
          needing_schema << db if dev_schema_md5 != get_schema_md5(db)
        end
      end
      needing_schema
    end

    def dev_schema_md5
      @dev_schema_md5 ||= `cat #{Swarm.schema_dump_path} | #{SCHEMA_SANITIZATION_SED} | #{MD5_CMD}`.strip
    end

    def get_schema_md5(db)
      `mysqldump --quick --no-data #{db_access_opts} #{db} | #{SCHEMA_SANITIZATION_SED} | #{MD5_CMD}`.strip
    end

    def dump_development_schema
      debug("Dumping schema...")
      development_db = ActiveRecord::Base.configurations['development']['database']
      system "mysqldump --quick --no-data #{db_access_opts} #{development_db} > #{Swarm.schema_dump_path}"
    end

    def choose_formatter
      @formatter = case ENV['FORMAT']
      when 'yaml'
        Formatter::YAMLFormatter.new(voice)
      else
        Formatter::FailFastProgressFormatter.new(voice)
      end
    end

    def voice
      @voice ||= Voice.new
    end

    def start_server
      FileUtils.rm(Swarm.socket_path) if File.exists?(Swarm.socket_path)
      @server = UNIXServer.new(Swarm.socket_path)
      yield
      @num_drones.times do
        begin
          drone_socket = @server.accept_nonblock
          start_drone_handler(drone_socket)
        rescue Errno::EAGAIN, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
          IO.select([@server])
          retry
        end
      end
    end

    def start_drone_handler(downlink)
      Thread.start do
        started_at = Time.now.to_f
        current_file = nil
        loop do
          begin
            directive = Directive.interpret(downlink.gets('end_directive'))
            case directive
            when Directive::TestFailed
              @formatter.test_failed(directive.detail)
            when Directive::TestPassed
              @formatter.test_passed
            when Directive::TestSkipped
              @formatter.test_skipped
            when Directive::TestPending
              @formatter.test_pending(directive.detail)
            when Directive::Ready
              notify_first_drone_ready

              begin
                if current_file
                  log_test_time(current_file, Time.now.to_f - started_at)
                  started_at = Time.now.to_f
                end
                file = @queue.pop(true)
                current_file = file
                downlink.puts(Directive.prepare(Directive::Exec.new(file)))
              rescue ThreadError
                downlink.puts(Directive.prepare(Directive::Quit))
                break
              end
            end
          rescue Exception => e
            puts e.message
            puts e.backtrace.join("\n") if e.backtrace
          end
        end
      end
    end

    def notify_first_drone_ready
      return if @notified
      @formatter.started
      @notified = true
    end

    def populate_queue
      @queue = Queue.new
      files = Drone.pilot.respond_to?(:split) ? Drone.pilot.split(Swarm.files) : Swarm.files

      files.sort do |a, b|
        test_time_for(b) <=> test_time_for(a)
      end.each { |file| @queue.push(file) }
    end

    def deploy_drones
      Drone.pilot.prepare
      @drone_config.each { |db, opts| deploy_drone(db, opts) }
    end

    def deploy_drone(db, options)
      fork { Drone.deploy(options.merge(:database => db)) }
    end

    def load_environment
      require File.dirname(__FILE__) + '/../../../../config/boot'
      require File.join(RAILS_ROOT, 'config', 'environment')
    end

    def detect_cores
      logical_cpu_count = case RUBY_PLATFORM
      when /darwin/
        `/usr/bin/hostinfo` =~ /(\d+) processors are logically available/ and $1
      when /linux/
        `cat /proc/cpuinfo | grep processor | wc -l`
      else
        raise "Swarm doesn't know how to detect the number of CPUs for #{RUBY_PLATFORM}"
      end.strip.to_i

      if ENV['NUM_SWARM_DRONES']
        @num_drones = ENV['NUM_SWARM_DRONES'].to_i # This shit below kills lucas' system so he's using this manual setting
      else
        @num_drones = (logical_cpu_count * 2 - (logical_cpu_count / 2)) # One process per logical cpu, minus one for imagemagick and not kill the system
      end

      debug("Detected #{logical_cpu_count} logical CPUs , deploying #{@num_drones} drones")
    end

    private

    def db_access_opts
      return @db_access_opts if defined? @db_access_opts
      str = []
      str << "-u #{@base_environment_configuration["username"]}" if @base_environment_configuration["username"]
      str << "-h #{@base_environment_configuration["host"]}" if @base_environment_configuration["host"]
      str << "-p#{@base_environment_configuration["password"]}" if @base_environment_configuration["password"]
      @db_access_opts = str.join ' '
    end
  end
end
