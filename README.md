# UploadIO

[![Crystal CI](https://github.com/mamantoha/upload_io/actions/workflows/crystal.yml/badge.svg)](https://github.com/mamantoha/upload_io/actions/workflows/crystal.yml)
[![GitHub release](https://img.shields.io/github/release/mamantoha/upload_io.svg)](https://github.com/mamantoha/upload_io/releases)
[![License](https://img.shields.io/github/license/mamantoha/upload_io.svg)](https://github.com/mamantoha/upload_io/blob/master/LICENSE)

`UploadIO` is a streaming upload library written in Crystal that integrates with `HTTP::Client`.

`UploadIO` instances can be used directly as the request body in `HTTP::Client` requests.
Since it implements the `IO` interface, `HTTP::Client` can read from it just like any other `IO` object.

It supports chunked uploads with a built-in progress callback.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     upload_io:
       github: mamantoha/upload_io
   ```

2. Run `shards install`

## Usage

This example demonstrates how to upload a file using `UploadIO` and `HTTP::Client` with chunked streaming and real-time progress tracking. The upload progress is displayed in bytes and percentage as the file is sent.

```crystal
require "upload_io"
require "http/client"

file = File.open("/path/to/file")
size = file.size
uploaded_total = 0
start_time = Time.monotonic

# Progress tracking callback
progress_tracker = ->(uploaded_chunk : Int32) do
  uploaded_total += uploaded_chunk
  elapsed_time = (Time.monotonic - start_time).total_seconds
  percentage = (uploaded_total * 100.0 / size).round(2)
  puts "Uploaded: #{uploaded_total} / #{size} bytes (#{percentage}%) in #{elapsed_time.round(2)}s"
end

upload_io = UploadIO.new(file, 4096, progress_tracker)

response = HTTP::Client.post("http://example.com/upload", body: upload_io)

total_time = (Time.monotonic - start_time).total_seconds
puts "Upload complete! Response: #{response.status_code} in #{total_time.round(2)} seconds"
```

Example output:

```
Uploaded: 4096 / 1048576 bytes (0.39%) in 0.01s
Uploaded: 8192 / 1048576 bytes (0.78%) in 0.02s
...
Uploaded: 1040384 / 1048576 bytes (99.22%) in 2.45s
Uploaded: 1044480 / 1048576 bytes (99.61%) in 2.48s
Uploaded: 1048576 / 1048576 bytes (100.0%) in 2.50s
Upload complete! Response: 200 in 2.50 seconds
```

## Contributing

1. Fork it (<https://github.com/mamantoha/upload_io/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Anton Maminov](https://github.com/mamantoha) - creator and maintainer
