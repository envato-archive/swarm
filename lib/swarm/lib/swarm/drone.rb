module Swarm
  class Drone
    include Singleton
    include OutputHelper

    def self.deploy(options)
      instance.deploy(options)
    end

    def self.pilot
      instance.pilot
    end

    def pilot
      @pilot ||= Swarm.drone_pilot.new(self)
    end

    def deploy(options)
      @options = options
      @name = "#{Process.pid}(#{@options[:database]})"

      begin
        recreate_database
        load_schema
        connect_to_database

        debug("Drone #{@name}: Directive::Ready")
        relay(Directive::Ready)

        loop do
          case directive = next_directive
          when Directive::Exec
            Dir.chdir(@options[:project_root])
            $0 = "Swarm: #{directive.file}"
            pilot.exec(directive)
          when Directive::Quit
            debug("Drone #{@name}: Directive::Quit")
            break
          end
        end
      rescue SystemExit
        exit 1
      rescue Exception => e
        puts e.message
        puts e.backtrace
      end
    end

    def relay(directive)
      begin
        uplink.puts(Directive.prepare(directive))
      rescue Errno::EPIPE
        debug("Drone #{@name}: Lost uplink to queen!")
        exit 1
      end
    end

    protected

    def recreate_database
      return if @options[:create_database] == false
      debug("Recreating #{@options[:database]}...")
      `mysqladmin #{@options[:db_access_opts]} -f --no-beep drop #{@options[:database]}`
      `mysqladmin #{@options[:db_access_opts]} -f --no-beep create #{@options[:database]}`
    end

    def load_schema
      return if @options[:reload_schema] == false
      debug("Loading schema into #{@options[:database]}...")
      `mysql #{@options[:db_access_opts]} #{@options[:database]} < #{Swarm.schema_dump_path}`
    end

    def connect_to_database
      ActiveRecord::Base.connection.disconnect!
      db_config = ActiveRecord::Base.configurations[Rails.env].merge('database' => @options[:database])
      ActiveRecord::Base.establish_connection(db_config)
    end

    def next_directive
      Directive.interpret(uplink.gets('end_directive'))
    end

    def uplink
      @uplink ||= UNIXSocket.open(Swarm.socket_path)
    end
  end
end
