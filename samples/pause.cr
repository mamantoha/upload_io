require "mime"
require "../src/upload_io"

if ARGV.size != 1
  puts "Usage: crystal pause.cr <file_path>"
  exit(1)
end

path = ARGV[0]

unless File.exists?(path)
  puts "Error: File not found - #{path}"
  exit(1)
end

url = "http://127.0.0.1:9909/upload"
file = File.open(path)
mime = MIME.from_filename(path)

chunk_size = 4_096
start_time = Time.monotonic
last_pause_time = start_time
is_uploading = true

upload_io = UploadIO.new(file, chunk_size)

# Create a fiber to handle pausing and resuming
spawn do
  while is_uploading
    elapsed = (Time.monotonic - start_time).total_seconds

    # Every second of active upload time (excluding paused time),
    # pause the upload for 10 seconds
    if elapsed - (last_pause_time - start_time).total_seconds >= 1
      puts "\nPausing upload..."
      upload_io.pause

      sleep 10.seconds
      puts "Resuming upload..."
      upload_io.resume

      last_pause_time = Time.monotonic
    end

    sleep 0.01.seconds
  end
end

headers = HTTP::Headers{
  "Content-Type"        => mime || "application/octet-stream",
  "Content-Disposition" => "attachment; filename=#{File.basename(path)}",
}

begin
  response = HTTP::Client.post(url, headers: headers, body: upload_io)
  total_time = (Time.monotonic - start_time).total_seconds
  puts "Upload complete! Response: #{response.status_code} #{response.body.inspect} in #{total_time.round(2)} seconds"
ensure
  is_uploading = false
end
