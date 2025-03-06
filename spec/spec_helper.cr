require "spec"
require "file_utils"
require "../src/upload_io"
require "./support/server"

SERVER_ADDRESS = "127.0.0.1"
SERVER_PORT    = 9909
SERVER_URL     = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

spawn { Server.run(SERVER_ADDRESS, SERVER_PORT) }

Spec.after_suite { remove_uploaded_files }

private def remove_uploaded_files
  Dir.glob("./spec/support/uploads/*").each do |file|
    FileUtils.rm(file)
  end
end
