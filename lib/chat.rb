$KCODE = 'UTF8'
require 'json'
require 'socket'
require 'logger'
require 'thread'
require 'chat/msg'
require 'chat/building'

Thread.abort_on_exception = $DEBUG

module Chat
  include Msg

  # Logger defined as a constant.
  Log = Logger.new(STDERR)
  Log.level = $DEBUG ? Logger::DEBUG : Logger::INFO

  # Our Errors so far.
  class ChatError < StandardError; end

  class InvalidCommand < ChatError; end

  class BuildingConstructionError < ChatError; end

  # Small mockup of a simple Authenticator.
  class Authenticator
    def initialize
      @logins = {
        'flori' => 'test',
        'alter' => 'ego',
      }
    end

    def allowed?(user_name, password)
      @logins[user_name] == password
    end
  end

  # The TCPConnectionHandler wraps a client's TCP connection and and processes
  # incoming messages from the client. If the messages are Room related the
  # message object is delegated to the room in question.
  class TCPConnectionHandler
    def initialize(connection)
      @connection = connection
    end

    # Returns <code>true</code> if the message <code>msg</code> was a login or
    # an unauthorized msg before a successful login. If the msg can be further
    # processed by the TCPConnectionHandler#process method, false  is returned.
    def login_related(msg)
      if Login === msg
        if @connection.server.authenticator.allowed?(
            msg.user_name, msg.password)
          @connection.user_name = msg.user_name
          @connection.send_msg(LoginOK.new)
          @connection.room.add_connection @connection
        else
          @connection.send_msg(LoginWrong.new)
        end
        return true
      elsif not @connection.authorized?
        @connection.send_msg Kick.new(
          "Unauthorized connections aren't allowed to send '#{msg.class}'!")
        @connection.force_close
        return true
      end
      false
    end

    # Process the message <code>msg_json</code>, that has to be a JSON encoded
    # string.
    def process(msg_json)
      msg = JSON.parse(msg_json)
      Log.debug 'Proc: ' + msg_json
      login_related(msg) and return
      # Login for this connection was granted before
      case msg
      when Alive
        @connection.alive
      when Logout
        @connection.room.remove_connection @connection
        @connection.send_msg LoggedOut.new
        @connection.force_close
      when Go, ListDoors, Public
        @connection.room.process(@connection, msg)
      else
        Log.warn "Didn't expect message '#{msg.class}': #{msg}"
      end
    end
  end

  # Small base class of our client/server-side tcp connections.
  class ConnectionSocket < TCPSocket
    def send_msg(msg)
      json = msg.to_json
      Log.debug 'Send: ' + json
      write json + "\n"
    end

    def recv_msg
      line = readline.chomp
      Log.debug 'Recv: ' + line
      JSON.parse(line)
    end
  end

  # This class wraps the incoming connections to the Server and decorates
  # it with useful attributes and methods.
  class Connection < ConnectionSocket
    def self.create(server, room, handle)
      obj = for_fd(handle)
      pa = obj.peeraddr
      obj.instance_eval do
        @server   = server
        @room     = room
        @handler  = nil
        @user_name = nil
        @peeraddr = pa[3]
        @peerport = pa[1]
        alive
      end
      obj
    end

    private_class_method :new

    attr_accessor   :user_name

    attr_reader     :server

    attr_reader     :room

    attr_reader     :lifesign

    def alive
      @lifesign = Time.now
    end

    def authorized?
      !!@user_name
    end

    def move(room_name)
      new_room = room.find_door(room_name) or return
      room.remove_connection self, room_name
      new_room.add_connection self
      @room = new_room
      true
    end

    def handle(thread)
      @thread = thread
      Log.info "Accepting connection from '#{self}'."
      until eof?
        line = readline
        if @handler
          @handler.process line
        else
          if m = /^POST (.*)/.match(line)
            url = m.captures
              # ...
            # if new connection
            # @handler = HTTPConnectionHandler.new(url)
            # else
            # @handler = HTTPCommandHandler.new(url)
            next
          else
            @handler = TCPConnectionHandler.new(self)
            @handler.process line
          end
        end
      end
    rescue StandardError
    ensure
      Log.info "Closing connection from '#{self}'."
      close unless closed?
    end

    def recv_msg
      super
      @lifesign = Time.now
    end

    def force_close
      close unless closed?
      @thread and @thread.kill
    end

    def close
      @room.remove_connection self
      super
    end

    def to_s
      "#@peeraddr:#@peerport"
    end
  end

  # This class instantiates our TCPServer, and drives the building consisting
  # of the different rooms.
  class Server < TCPServer
    def initialize(hostname, port, building)
      super(hostname, port)
      @hostname, @port  = hostname, port
      @authenticator    = Authenticator.new
      @building         = building
    end

    attr_reader :authenticator

    def accept
      Connection.create(self, @building.start_room, sysaccept)
    end

    def run
      Log.info "Now accepting connections on '#@hostname:#@port'."
      Thread.new do
        loop do
          sleep 1
          now = Time.now
          @building.each do |r|
            r.each do |c|
              c.send_msg KeepAlive.new if now - c.lifesign > 60
            end
          end
        end
      end
      loop do
        Thread.new(accept) do |c|
          c.handle Thread.current
        end
      end
    end
  end

  # Class to instantiate a connection to the Server.
  class Client < ConnectionSocket
    def initialize(hostname, port)
      super
    end

    attr_reader :user_name

    def login(user_name, password)
      return if @logged_in
      @user_name = user_name
      send_msg Login.new(user_name, password)
      result = recv_msg
      case result
      when LoginOK
        @logged_in = true
      when LoginWrong
        false
      else
        raise InvalidCommand, "Didn't expect message '#{result.class}'."
      end
    end

    def public(text)
      send_msg Public.new(text)
    end

    def go(room_name)
      send_msg Go.new(room_name)
    end

    def list_doors
      send_msg ListDoors.new
    end

    def logout
      send_msg Logout.new
    end
  end
end

if $0 == __FILE__
  include Chat

  if ARGV.empty?
    building    = Building.new { 'lobby' }
    lobby       = building.build_room 'lobby'
    kitchen     = building.build_room 'kitchen'
    balcony     = building.build_room 'balcony'
    living_room = building.build_room 'living_room'
    toilet      = building.build_room 'toilet'
    lobby.add_door        living_room
    living_room.add_door  toilet
    living_room.add_door  kitchen
    kitchen.add_door      balcony
    balcony.add_door      living_room
    s = Server.new(nil, 6666, building)
    s.run
  else
    c = Client.new(*ARGV[0, 2])
    result = c.login(*ARGV[2, 2])
    if result
      puts "Logged in."
      Thread.new do
        begin
          loop do
            msg = c.recv_msg 
            case msg
            when KeepAlive
              c.send_msg Alive.new
            when LoggedOut
              puts "Bye."
              exit
            else
              puts msg
            end
          end
        rescue StandardError
          exit 1
        end
      end
      while line = STDIN.readline.chomp
        if %r(^/(\w+)\s*(.*)).match line
          begin
            c.__send__($1, *($2.split(/,/)))
          rescue NoMethodError, ArgumentError => e
            warn "Caught: #{e.class} - #{e}"
          end
        else
          c.public line
        end
      end
    else
      puts "Login failed!"
      exit 1
    end
  end
end
  # vim: set et sw=2 ts=2:
