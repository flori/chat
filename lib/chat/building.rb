module Chat
  class Building
    # Constructs a Building object. If a block is given, it is called to
    # compute the name of the start_room of the building. The default is to
    # start at a random room of <code>rooms</code>.
    def initialize(&compute_start_room)
      @rooms = {}
      if block_given?
        @compute_start_room = compute_start_room
      else
        @compute_start_room = lambda { @rooms.keys[rand(@rooms.size)] }
      end
    end

    # A hash mapping between room names and rooms.
    attr_reader :rooms

    # Builds another room (class Room) in the building, named
    # <code>room_name</code>, and returns it. If there already is a room with
    # this name, a BuildingConstructionError is raised.
    def build_room(room_name)
      if @rooms.key?(room_name)
        raise BuildingConstructionError, "Room #{room_name} already part of building!"
      end
      @rooms[room_name] = Room.new room_name
    end

    # Returns the room with name <code>room_name</code>
    def [](room_name)
      @rooms[room_name]
    end

    # Returns the start rooms.
    def start_room
      self[@compute_start_room[]]
    end

    # Iterates over all rooms of the building.
    def each(&block)
      @rooms.each_value(&block)
    end
    include Enumerable
  end

  class Room
    # Constructs a Room instance named <code>name</code>.
    def initialize(name)
      @name           = name
      @connections    = {}
      @doors          = []
    end

    # The name of this room.
    attr_reader :name

    # A door to room <code>room</code> is added to this room.
    def add_door(room)
      return if self == room or @doors.include? room
      @doors << room
      room.add_door self
    end

    # A connection/user is added to this Room.
    def add_connection(connection)
      if old_connection = @connections[connection.user_name]
        old_connection.send_msg Kick.new(
          "Logged out because you're entering room '#@name' again!")
        old_connection.force_close
      end
      each do |c|
        c.send_msg EnterRoom.new(connection.user_name)
      end
      @connections[connection.user_name] = connection
      connection.send_msg EnteredRoom.new(name, @connections.keys)
      self
    end

    # A connection/user is removed from this Room.
    def remove_connection(connection, new_room = nil)
      @connections.delete_if { |_,c| c == connection }
      each do |c|
        c.send_msg LeftRoom.new(connection.user_name, new_room)
      end
      self
    end

    # Returns true, if a connection/user is already in this room.
    def has_connection?(connection)
      @connections.has_value? connection
    end

    # Trys to find a door to room <code>room_name</code> and returns
    # this room if successful. Otherwise nil is returned.
    def find_door(room_name)
      @doors.find { |r| r.name == room_name }
    end

    # Iterates over all connections/users in this room.
    def each(&block)
      @connections.values.each(&block)
      self
    end
    include Enumerable

    def count_users # XXX unused
      s = 0; each { s +=1 }; s
    end

    # Process the Room related <code>msg</code>, that came in from
    # <code>connection</code>.
    def process(connection, msg)
      case msg
      when Public
        pb = PublicBroadcast.new(connection.user_name, msg.text)
        each { |c| c.send_msg pb }
      when ListDoors
        connection.send_msg ListedDoors.new(@doors.map { |r| r.name })
      when Go
        connection.move(msg.room_name) or
          Log.debug "Couldn't move to this room: #{msg.to_json}"
      else
        Log.warn "Didn't expect message '#{msg.class}': #{msg.to_json}"
      end
      self
    end
  end
end
  # vim: set et sw=2 ts=2:
