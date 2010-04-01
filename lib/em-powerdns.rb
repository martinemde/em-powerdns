require 'eventmachine'

# Instances of this class wrap the PowerDNS I/O stream with a nice API
module EventMachine::Protocols
  module PowerDNS
    class Error < RuntimeError
      attr_reader :original_exception

      def initialize(data, exception)
        @original_exception = exception
        super "Unexpected error in the EM::P::PowerDNS:\nPowerDNS Data: #{data.inspect}\nError: #{exception}\n#{exception.backtrace}"
      end
    end

    include EM::Protocols::LineText2
    include Output

    SEPARATOR = "\t"
    EVENT_MAP = Hash.new(:receive_garbage)
    EVENT_MAP.update(
      'HELO' => :receive_raw_handshake,
      'Q'    => :receive_raw_query,
      'AXFR' => :receive_raw_axfr,
      'PING' => :receive_raw_ping
    )

    def self.start
      EM.open_keyboard(self)
    end

    def initialize
      $stdin.sync = true
      $stdout.sync = true
    end

    def receive_line(data)
      parts = data.split SEPARATOR
      type = parts.shift
      send EVENT_MAP[type], *parts
    rescue => e
      receive_error Error.new(data, e)
    end

    def receive_raw_handshake(*parts)
      @version = parts.first.to_i
      if [1,2].include?(@version)
        receive_handshake(@version)
      else
        fail "Received unexpected handshake: #{parts.inspect}"
      end
    end

    def receive_handshake(version)
      ok "Backend starting version #{version}."
    end

    class Query < Struct.new(:qname, :qclass, :qtype, :id, :remote_ip, :local_ip)
    end

    def receive_raw_query(*parts)
      if parts.size != parts_size_for_version
        fail "Received unexpected format for Q: #{parts.inspect}"
      else
        query = Query.new(*parts)
        receive_query(query)
      end
    end

    def parts_size_for_version
      @version == 1 ? 5 : 6 # already chopped off the 'Q'
    end

    # Stub method for users implementing this protocol
    def receive_query(query)
      done
    end

    def receive_raw_axfr(*parts)
      if parts.size != 1
        fail "Received unexpected format for AXFR: #{parts.inspect}"
      else
        receive_axfr(parts.first)
      end
    end

    # Stub method for users implementing this protocol
    def receive_axfr(soa_resource)
      done
    end

    def receive_raw_ping(*parts)
      receive_ping
    end

    # Stub method for users implementing this protocol
    def receive_ping
      done
    end

    def receive_garbage(line)
      fail "Unknown Question: #{line.inspect}"
    end

    def receive_error(error)
      fail "An unexpected error occurred in backend: #{error.original_exception.message}"
      raise error
    end
    module Output
    def ok(line)
      send_line "OK", line
    end

    def data(*parts)
      send_line "DATA", *parts
    end

    def log(line)
      send_line "LOG", line
    end

    def fail(line = nil)
      log(line) if line
      send_line "FAIL"
    end

    def done(line = nil)
      log(line) if line
      send_line "END"
    end

    def send_line(*parts)
      send_data parts.join(PowerDNS::Connection::SEPARATOR)
    end

    def send_data(data)
      $stdout.puts data
    end
  end
end
