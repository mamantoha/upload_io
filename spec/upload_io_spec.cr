require "./spec_helper"
require "../src/upload_io"

describe UploadIO do
  it "uploads data from Bytes" do
    data = Bytes.new(8192) { 1_u8 }

    chunks = [] of Int32

    upload_io = UploadIO.new(data, 4096, ->(chunk_size : Int32) {
      chunks << chunk_size
    })

    buffer = Bytes.new(4096)

    while (bytes_read = upload_io.read(buffer)) > 0
      buffer[0, bytes_read]
    end

    upload_io.uploaded.should eq 8192
    chunks.should eq [4096, 4096]
  end

  it "uploads data from String" do
    data = "Hello, World! This is a test string for UploadIO."
    chunks = [] of Int32

    progress_tracker = ->(chunk_size : Int32) do
      chunks << chunk_size
    end

    upload_io = UploadIO.new(data, 10, progress_tracker)

    buffer = Bytes.new(10)

    while (bytes_read = upload_io.read(buffer)) > 0
      buffer[0, bytes_read]
    end

    upload_io.uploaded.should eq data.bytesize
    chunks.should eq [10, 10, 10, 10, 9]
  end

  it "uploads data from IO" do
    io = IO::Memory.new("This is a streamed test.")
    chunks = [] of Int32

    upload_io = UploadIO.new(io, 8, ->(chunk_size : Int32) {
      chunks << chunk_size
    })

    buffer = Bytes.new(8)

    while (bytes_read = upload_io.read(buffer)) > 0
      buffer[0, bytes_read]
    end

    upload_io.uploaded.should eq io.to_s.bytesize
    chunks.should eq [8, 8, 8, 0]
  end

  it "handles Nil input gracefully" do
    upload_io = UploadIO.new(nil, 4096)
    buffer = Bytes.new(4096)

    upload_io.read(buffer).should eq 0
    upload_io.uploaded.should eq 0
  end

  it "triggers on_progress callback correctly" do
    data = Bytes.new(1024) { 1_u8 }
    calls = [] of Int32

    upload_io = UploadIO.new(data, 256, ->(chunk_size : Int32) {
      calls << chunk_size
    })

    buffer = Bytes.new(256)

    while (bytes_read = upload_io.read(buffer)) > 0
      buffer[0, bytes_read]
    end

    calls.should eq [256, 256, 256, 256]
  end

  describe ".on_progress" do
    it "triggers callback correctly" do
      data = Bytes.new(1024) { 1_u8 }
      calls = [] of Int32

      upload_io = UploadIO.new(data, 256)

      upload_io.on_progress = ->(chunk_size : Int32) {
        calls << chunk_size
      }

      buffer = Bytes.new(256)

      while (bytes_read = upload_io.read(buffer)) > 0
        buffer[0, bytes_read]
      end

      calls.should eq [256, 256, 256, 256]
    end
  end

  describe "cancel functionality" do
    it "cancels upload when should_cancel returns true" do
      data = Bytes.new(8192) { 1_u8 }
      read_count = 0

      upload_io = UploadIO.new(
        data,
        4096,
        nil,
        -> {
          read_count += 1
          read_count > 1 # Cancel after first chunk
        }
      )

      buffer = Bytes.new(4096)

      while (bytes_read = upload_io.read(buffer)) > 0
        buffer[0, bytes_read]
      end

      upload_io.uploaded.should eq 4096
    end

    it "continues upload when should_cancel returns false" do
      data = Bytes.new(8192) { 1_u8 }

      upload_io = UploadIO.new(data, 4096, nil, -> { false })

      buffer = Bytes.new(4096)

      while (bytes_read = upload_io.read(buffer)) > 0
        buffer[0, bytes_read]
      end

      upload_io.uploaded.should eq 8192
    end

    it "handles nil should_cancel callback" do
      data = Bytes.new(8192) { 1_u8 }
      chunks = [] of Int32

      upload_io = UploadIO.new(
        data,
        4096,
        ->(chunk_size : Int32) {
          chunks << chunk_size
        }
      )

      buffer = Bytes.new(4096)

      while (bytes_read = upload_io.read(buffer)) > 0
        buffer[0, bytes_read]
      end

      upload_io.uploaded.should eq 8192
      chunks.should eq [4096, 4096]
    end

    describe "cancel method" do
      it "stops upload after cancel is called" do
        data = Bytes.new(8192) { 1_u8 }
        chunks = [] of Int32

        upload_io = UploadIO.new(
          data,
          4096,
          ->(chunk_size : Int32) {
            chunks << chunk_size
          }
        )

        buffer = Bytes.new(4096)

        # Read first chunk
        bytes_read = upload_io.read(buffer)
        bytes_read.should eq 4096

        # Cancel upload
        upload_io.cancel

        # Try to read more
        bytes_read = upload_io.read(buffer)
        bytes_read.should eq 0

        upload_io.uploaded.should eq 4096
        chunks.should eq [4096]
      end

      it "closes IO source when cancelled" do
        io = IO::Memory.new("This is a streamed test.")

        upload_io = UploadIO.new(io, 8)

        buffer = Bytes.new(8)

        # Read first chunk
        bytes_read = upload_io.read(buffer)
        bytes_read.should eq 8

        # Cancel upload
        upload_io.cancel

        # IO should be closed
        io.closed?.should be_true

        upload_io.uploaded.should eq 8
      end
    end

    describe ".should_cancel" do
      it "triggers callback correctly" do
        data = Bytes.new(4096 * 8) { 1_u8 }
        read_count = 0

        upload_io = UploadIO.new(data, 4096)

        upload_io.should_cancel = -> {
          read_count += 1
          read_count > 1 # Cancel after first chunk
        }

        buffer = Bytes.new(4096)

        while (bytes_read = upload_io.read(buffer)) > 0
          buffer[0, bytes_read]
        end

        upload_io.uploaded.should eq 4096
      end
    end
  end

  describe "pause/resume functionality" do
    it "pauses and resumes upload" do
      # Initialize test data and trackers
      data = Bytes.new(8192) { 1_u8 }
      chunks = [] of Int32
      read_channel = Channel(Nil).new

      # Create UploadIO with 4KB chunks and progress tracking
      upload_io = UploadIO.new(
        data,
        4096,
        ->(chunk_size : Int32) {
          chunks << chunk_size
        }
      )

      buffer = Bytes.new(4096)

      # Read first chunk (4KB) - this should complete immediately
      bytes_read = upload_io.read(buffer)
      bytes_read.should eq 4096
      chunks.should eq [4096] # Verify first chunk was uploaded

      # Pause the upload - subsequent reads will block until resume
      upload_io.pause
      upload_io.paused?.should be_true

      # Start reading the second chunk in a separate fiber
      # This read will block because the upload is paused
      spawn do
        upload_io.read(buffer)
        read_channel.send(nil) # Signal when read completes
      end

      # Give the fiber a moment to start and verify it's blocked
      sleep 0.1.seconds
      chunks.should eq [4096] # Verify no new chunks were uploaded while paused

      # Resume the upload - this will unblock the waiting read
      upload_io.resume
      upload_io.paused?.should be_false

      # Wait for the blocked read to complete
      read_channel.receive
      chunks.should eq [4096, 4096] # Verify second chunk was uploaded after resume

      # Verify final state
      upload_io.uploaded.should eq 8192
      chunks.should eq [4096, 4096]
    end
  end

  describe "speed limiting" do
    it "limits upload speed to specified bytes per second" do
      # Create a test file with 1MB of data
      test_data = Bytes.new(1_048_576, 0_u8)
      io = IO::Memory.new(test_data)

      # Set speed limit to 100KB/s (102,400 bytes/s)
      max_speed = 102_400
      upload_io = UploadIO.new(io, 4096, max_speed: max_speed)

      # Read all data and measure time
      buffer = Bytes.new(4096)
      start_time = Time.monotonic
      total_read = 0

      while (read = upload_io.read(buffer)) > 0
        total_read += read
      end

      elapsed_time = (Time.monotonic - start_time).total_seconds
      actual_speed = total_read / elapsed_time

      # Verify actual speed is within 15% of max speed
      margin = 0.15
      min_speed = max_speed * (1 - margin)
      max_speed_with_margin = max_speed * (1 + margin)

      actual_speed.should be >= min_speed
      actual_speed.should be <= max_speed_with_margin

      # Verify total upload time is approximately 10.24 seconds
      expected_time = 10.24
      min_time = expected_time * (1 - margin)
      max_time = expected_time * (1 + margin)

      elapsed_time.should be >= min_time
      elapsed_time.should be <= max_time
    end
  end
end
