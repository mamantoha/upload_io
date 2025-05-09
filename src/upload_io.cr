require "http/client"

# `UploadIO` instances can be used directly as the request body in `HTTP::Client` requests.
# Since it implements the `IO` interface, `HTTP::Client` can read from it just like any other `IO` object.

# `UploadIO` supports chunked uploads with a built-in progress callback
# and provides upload cancellation through either a callback or direct method call.
#
# ```
# require "upload_io"
# require "http/client"
#
# file = File.open("/path/to/file")
# size = file.size
# uploaded_total = 0
#
# upload_io = UploadIO.new(file, 4096, ->(uploaded_chunk : Int32) {
#   uploaded_total += uploaded_chunk
#   puts "Uploaded: #{uploaded_total} / #{size} bytes"
# })
#
# headers = HTTP::Headers{
#   "Content-Type"   => "application/octet-stream",
#   "Content-Length" => size.to_s,
# }
#
# response = HTTP::Client.post("http://example.com/upload", headers: headers, body: upload_io)
# puts "Upload complete! Response: #{response.status_code}"
# ```
class UploadIO < IO
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}

  CHUNK_SIZE = 4096

  # Tracks the total bytes uploaded so far.
  getter uploaded : Int64 = 0

  # Returns true if the upload has been cancelled
  getter? cancelled : Bool = false

  # Returns true if the upload is currently paused
  getter? paused : Bool = false

  # Maximum upload speed in bytes per second. If nil, no speed limit is applied.
  property max_speed : Int64?

  # Creates a new `UploadIO` with given arguments.
  #
  # - `data` - the upload data source
  # - `chunk_size` - the size of each chunk to be read
  # - `on_progress` - optional callback to track progress
  # - `should_cancel` - optional callback to control upload cancellation
  # - `max_speed` - optional maximum upload speed in bytes per second
  def initialize(
    @data : HTTP::Client::BodyType,
    @chunk_size : Int32,
    @on_progress : Proc(Int32, Nil)? = nil,
    @should_cancel : Proc(Bool)? = nil,
    *,
    @max_speed : Int64? = nil,
  )
    super()

    @is_io = false
    @size = 0
    @rewound = false
    @cancelled = false
    @paused = false
    @last_read_time = Time.monotonic
    @bytes_in_window = 0_i64
    @window_start = Time.monotonic

    case @data
    in IO
      @is_io = true
    in Bytes
      @size = @data.as(Bytes).size
    in String
      @data = @data.as(String).to_slice
      @size = @data.as(Bytes).size
    in Nil
    end

    @offset = 0_i64 # Track position (only used for Bytes or String)
  end

  # Creates a new `UploadIO` with a block for configuration.
  #
  # ```
  # file = File.open("/path/to/file")
  # size = file.size
  # uploaded_total = 0
  #
  # upload_io = UploadIO.new(file) do |io|
  #   io.on_progress ->(uploaded_chunk : Int32) do
  #     uploaded_total += uploaded_chunk
  #     puts "Uploaded: #{uploaded_total} / #{size} bytes"
  #   end
  #
  #   io.should_cancel -> { uploaded_total >= size / 2 }
  #   io.max_speed = 125_000 # 1 Mbps
  # end
  #
  # response = HTTP::Client.post("http://example.com/upload", body: upload_io)
  # ```
  def self.new(data : HTTP::Client::BodyType, chunk_size : Int32 = CHUNK_SIZE, &block : self ->)
    io = new(data, chunk_size)
    block.call(io)
    io
  end

  def self.new(
    data : HTTP::Client::BodyType,
    on_progress : Proc(Int32, Nil)? = nil,
    should_cancel : Proc(Bool)? = nil,
    *,
    max_speed : Int64? = nil,
  )
    new(data, CHUNK_SIZE, on_progress, should_cancel, max_speed: max_speed)
  end

  # Optional callback function that receives the size of each uploaded chunk.
  #
  # ```
  # file = File.open("/path/to/file")
  # size = file.size
  # uploaded_total = 0
  #
  # upload_io = UploadIO.new(file)
  # upload_io.on_progress ->(uploaded_chunk : Int32) do
  #   uploaded_total += uploaded_chunk
  #   puts "Uploaded: #{uploaded_total} / #{size} bytes"
  # end
  #
  # response = HTTP::Client.post("http://example.com/upload", body: upload_io)
  # ```
  def on_progress(on_progress : Proc(Int32, Nil))
    @on_progress = on_progress
  end

  # Optional callback function that determines if the upload should be cancelled.
  # Return true to cancel the upload.
  #
  # ```
  # file = File.open("/path/to/file")
  # start_time = Time.monotonic
  #
  # upload_io = UploadIO.new(file)
  # # Stop upload after 5 seconds
  # upload_io.should_cancel -> { (Time.monotonic - start_time).total_seconds > 5 }
  #
  # response = HTTP::Client.post("http://example.com/upload", body: upload_io)
  # ```
  def should_cancel(should_cancel : Proc(Bool))
    @should_cancel = should_cancel
  end

  # Cancels the upload process. After calling this method:
  # - Subsequent reads will return 0 bytes
  # - If the data source is an IO, it will be closed
  # - The upload cannot be resumed
  def cancel
    return if cancelled?

    @cancelled = true

    if @is_io && @data.is_a?(IO)
      @data.as(IO).close
    end
  end

  # Pauses the upload process. While paused:
  # - Subsequent reads will block until `resume` is called
  # - The upload can be resumed using the `resume` method
  def pause
    @paused = true
  end

  # Resumes a paused upload. After calling this method:
  # - Subsequent reads will continue from where they left off
  def resume
    @paused = false
  end

  private def calculate_wait_time(bytes_read : Int32) : Time::Span
    return Time::Span.zero unless @max_speed

    current_time = Time.monotonic
    window_duration = (current_time - @window_start).total_seconds

    # Reset window if it's been more than 1 second
    if window_duration >= 1.0
      @bytes_in_window = 0
      @window_start = current_time
      window_duration = 0.0
    end

    @bytes_in_window += bytes_read

    # Calculate how long we should wait to maintain the speed limit
    # ameba:disable Lint/NotNil
    target_duration = @bytes_in_window.to_f / @max_speed.not_nil!
    wait_time = target_duration - window_duration

    # Don't wait if we're already slower than the limit
    wait_time > 0 ? Time::Span.new(nanoseconds: (wait_time * 1_000_000_000).to_i64) : Time::Span.zero
  end

  # Reads the next chunk of data and copies it into the provided buffer.
  #
  # This method is called automatically by `HTTP::Client` when sending data.
  # It reads up to `chunk_size` bytes and updates the upload progress.
  #
  # Returns the number of bytes that will be sent to the server (not the total send bytes),
  # which is 0 if and only if there is no more data to reads
  # (so checking for 0 is the way to detect end of file).
  #
  # Since `UploadIO` only provides data to `HTTP::Client`,
  # we can only track the amount of data read and not the actual bytes transmitted to the server.
  def read(slice : Bytes) : Int32
    return 0 if @rewound || cancelled?
    return 0 if @should_cancel.try &.call
    return 0 unless @data

    while paused?
      sleep 0.1.seconds
    end

    if @is_io
      # read directly into the provided buffer
      bytes_to_send = @data.as(IO).read(slice)
    else
      remaining = @size - @offset

      return 0 if remaining <= 0

      bytes_to_send = [@chunk_size, remaining].min
      chunk = @data.as(Bytes)[@offset, bytes_to_send] # extract chunk from data

      slice.copy_from(chunk)
      @offset += bytes_to_send
    end

    @uploaded += bytes_to_send

    @on_progress.try &.call(bytes_to_send)

    # Apply speed limiting if configured
    sleep(calculate_wait_time(bytes_to_send))

    bytes_to_send
  end

  # Required method by `IO` but not used in `UploadIO`.
  #
  # `UploadIO` is read-only, so `write` does nothing.
  def write(slice : Bytes) : Nil
    nil
  end

  def rewind
    @offset = 0
    @uploaded = 0
    @rewound = true
    @last_read_time = Time.monotonic
    @bytes_in_window = 0
    @window_start = Time.monotonic
  end
end
