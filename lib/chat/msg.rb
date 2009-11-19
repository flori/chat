module Chat
  module Msg

    # Baseclass for all messages. Sets up some messages to make Message class
    # definition nicer.
    class Message
      ALL = []

      def self.inherited(klass)
        ALL << klass
      end

      def self.fields
        @fields ||= []
      end

      def self.def_fields(*fields)
        self.instance_variable_set :@fields, fields.map { |f| f.to_s }
        self.__send__ :attr_reader, *@fields
        self
      end

      def self.json_create(o)
        new(*o.values_at(*fields))
      end

      def initialize(*values)
        self.class.fields.each_with_index do |f, i|
          instance_variable_set "@#{f}", values[i]
        end
      end

      def to_json
        hash = { 'json_class'  => self.class }
        self.class.fields.each do |f|
          hash[f] = instance_variable_get "@#{f}"
        end
        hash.to_json
      end
    end

    # C->S: Login as user <code>user_name</code> with password
    # <code>password</code>.
    class Login < Message
      def_fields :user_name, :password
    end

    # S->C: Login was OK, that is access was granted.
    class LoginOK < Message; end

    # S->C: Login failed, that is access was denied.
    class LoginWrong < Message; end

    # S->C: The server sends this message and expects, the client to respond
    # with an Alive message.
    class KeepAlive < Message; end

    # C->S: If the client receives a KeepAlive message, it should respond with
    # an Alive message.
    class Alive < Message; end

    # C->S: Tell the server to disconnect this user.
    class Logout < Message; end

    # S->C: Response to the Logout message after disconnection.
    class LoggedOut < Message; end

    # S->C: XXX
    class Kick < Message
      def_fields :text
    end

    # C->S: The user sends a Public message, that can be heard by everybody in
    # the current room.
    class Public < Message
      def_fields :text
    end

    # S->C: Created from a user's public message and broadcasted to all users
    # in the room <code>room_name</code> XXX.
    class PublicBroadcast < Message
      def_fields :user_name, :text#, :room_name

      def to_s
        "#{user_name}: #{text}"
      end
    end

    # S->C: All users in a room are informed that the use <code>user_name</code>
    # has just entered the room by the message EnterRoom.
    class EnterRoom < Message
      def_fields :user_name

      def to_s
        "#{user_name} enters the room."
      end
    end

    # S->C: Entering room <code>room_name</code> was successful. The array
    # <code>users</code> holds all the users in the room at this time.
    class EnteredRoom < Message
      def_fields :room_name, :users

      def to_s
        "You're in the #{room_name}, together with #{users.join(', ')}."
      end
    end

    # S->C: Message is sent if a user <code>user_name</code> leaves the room. If
    # he goes into an adjacent room, <code>to_room</code> contains the name of
    # this room. If the user leaves the server, <code>to_room</code> is nil.
    class LeftRoom < Message
      def_fields :user_name, :to_room

      def to_s
        "#{user_name} has just left the room" +
          (to_room ? ", and went to the #{to_room}." : ".")
      end
    end

    # C->S: If the user wants to go into room <code>room_name</code>, a Go message
    # is sent.
    class Go < Message
      def_fields :room_name
    end

    # C->S: List all the doors to the adjacent rooms.
    class ListDoors < Message; end

    # S->C: List every door:
    class ListedDoors < Message
      def_fields :doors

      def to_s
        "doors = { #{doors.join(', ')} }"
      end
    end
  end
end
