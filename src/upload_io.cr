require "http/client"

# `UploadIO` instances can be used directly as the request body in `HTTP::Client` requests.
# Since it implements the `IO` interface, `HTTP::Client` can read from it just like any other `IO` object.

# It supports chunked uploads with a built-in progress callback.
#
# ```crystal
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
# client = HTTP::Client.new(URI.parse("http://example.com/upload"))
# headers = HTTP::Headers{
#   "Content-Type"   => "application/octet-stream",
#   "Content-Length" => size.to_s,
# }
#
# response = client.post("http://example.com/upload", headers: headers, body: upload_io)
# puts "Upload complete! Response: #{response.status_code}"
# ```
class UploadIO < IO
  CHUNK_SIZE = 4096

  # Tracks the total bytes uploaded so far.
  getter uploaded : Int64 = 0

  # Optional callback function that receives the size of each uploaded chunk.
  getter on_progress : Proc(Int32, Nil)?

  # `data` - the upload data source
  # `chunk_size` - the size of each chunk to be read
  # `on_progress` - optional callback to track progress
  def initialize(@data : HTTP::Client::BodyType, @chunk_size : Int32, @on_progress : Proc(Int32, Nil)? = nil)
    super()

    @is_io = false
    @size = 0

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

  def self.new(data : HTTP::Client::BodyType, on_progress : Proc(Int32, Nil)? = nil)
    new(data, CHUNK_SIZE, on_progress)
  end

  # Reads the next chunk of data and copies it into the provided buffer.
  #
  # This method is called automatically by `HTTP::Client` when sending data.
  # It reads up to `chunk_size` bytes and updates the upload progress.
  #
  # Returns the number of bytes that will be sent to the server (not the total sent bytes).
  #
  # Since `UploadIO` only provides data to `HTTP::Client`,
  # we can only track the amount of data read and not the actual bytes transmitted to the server.
  def read(slice : Bytes) : Int32
    return 0 unless @data

    bytes_to_send = @chunk_size

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

    bytes_to_send
  end

  # Required method by `IO` but not used in `UploadIO`.
  #
  # `UploadIO` is read-only, so `write` does nothing.
  def write(slice : Bytes) : Nil
    nil
  end
end
