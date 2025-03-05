require "spec"
require "../src/upload_io"
require "./support/server"

SERVER_ADDRESS = "0.0.0.0"
SERVER_PORT    = 9909
SERVER_URL     = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

spawn { Server.run(SERVER_ADDRESS, SERVER_PORT) }
