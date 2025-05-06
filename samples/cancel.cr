require "../src/upload_io"
require "http/client"

if ARGV.size != 1
  puts "Usage: crystal cancel.cr <file_path>"
  exit(1)
end

path = ARGV[0]

unless File.exists?(path)
  puts "Error: File not found - #{path}"
  exit(1)
end

file = File.open(path)
size = file.size
uploaded_total = 0

upload_io = UploadIO.new(file, 4096, ->(uploaded_chunk : Int32) {
  uploaded_total += uploaded_chunk
  puts "Uploaded: #{uploaded_total} / #{size} bytes"
})

url = "http://speedtest.astra.in.ua.prod.hosts.ooklaserver.net:8080/upload"

# Start the upload in a separate fiber
spawn do
  headers = HTTP::Headers{
    "Content-Type"   => "application/octet-stream",
    "Content-Length" => size.to_s,
  }
  response = HTTP::Client.post(url, headers: headers, body: upload_io)
  puts "Upload complete! Response: #{response.status_code}"
end

# Cancel the upload after 5 seconds
sleep 5
upload_io.cancel
puts "Upload cancelled after #{upload_io.uploaded} bytes"
