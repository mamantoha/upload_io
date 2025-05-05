require "./spec_helper"
require "../src/upload_io"

describe UploadIO do
  it "uploads data from Bytes" do
    data = Bytes.new(8192) { 1_u8 }

    uploaded_total = 0
    chunks = [] of Int32

    upload_io = UploadIO.new(data, 4096, ->(chunk_size : Int32) {
      uploaded_total += chunk_size
      chunks << chunk_size
    })

    buffer = Bytes.new(4096)

    while (bytes_read = upload_io.read(buffer)) > 0
      buffer[0, bytes_read]
    end

    upload_io.uploaded.should eq 8192
    uploaded_total.should eq 8192
    chunks.should eq [4096, 4096]
  end

  it "uploads data from String" do
    data = "Hello, World! This is a test string for UploadIO."
    uploaded_total = 0

    progress_tracker = ->(chunk_size : Int32) do
      uploaded_total += chunk_size
    end

    upload_io = UploadIO.new(data, 10, progress_tracker)

    buffer = Bytes.new(10)

    while (bytes_read = upload_io.read(buffer)) > 0
      buffer[0, bytes_read]
    end

    upload_io.uploaded.should eq data.bytesize
    uploaded_total.should eq data.bytesize
  end

  it "uploads data from IO" do
    io = IO::Memory.new("This is a streamed test.")
    uploaded_total = 0

    upload_io = UploadIO.new(io, 8, ->(chunk_size : Int32) {
      uploaded_total += chunk_size
    })

    buffer = Bytes.new(8)

    while (bytes_read = upload_io.read(buffer)) > 0
      buffer[0, bytes_read]
    end

    upload_io.uploaded.should eq io.to_s.bytesize
    uploaded_total.should eq io.to_s.bytesize
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

  describe "cancel functionality" do
    it "cancels upload when should_cancel returns true" do
      data = Bytes.new(8192) { 1_u8 }
      uploaded_total = 0
      chunks = [] of Int32
      read_count = 0

      upload_io = UploadIO.new(
        data,
        4096,
        ->(chunk_size : Int32) {
          uploaded_total += chunk_size
          chunks << chunk_size
        },
        ->(nil : Nil) {
          read_count += 1
          read_count > 1 # Cancel after first chunk
        }
      )

      buffer = Bytes.new(4096)

      while (bytes_read = upload_io.read(buffer)) > 0
        buffer[0, bytes_read]
      end

      upload_io.uploaded.should eq 4096
      uploaded_total.should eq 4096
      chunks.should eq [4096]
    end

    it "continues upload when should_cancel returns false" do
      data = Bytes.new(8192) { 1_u8 }
      uploaded_total = 0
      chunks = [] of Int32

      upload_io = UploadIO.new(
        data,
        4096,
        ->(chunk_size : Int32) {
          uploaded_total += chunk_size
          chunks << chunk_size
        },
        ->(nil : Nil) { false }
      )

      buffer = Bytes.new(4096)

      while (bytes_read = upload_io.read(buffer)) > 0
        buffer[0, bytes_read]
      end

      upload_io.uploaded.should eq 8192
      uploaded_total.should eq 8192
      chunks.should eq [4096, 4096]
    end

    it "handles nil should_cancel callback" do
      data = Bytes.new(8192) { 1_u8 }
      uploaded_total = 0
      chunks = [] of Int32

      upload_io = UploadIO.new(
        data,
        4096,
        ->(chunk_size : Int32) {
          uploaded_total += chunk_size
          chunks << chunk_size
        }
      )

      buffer = Bytes.new(4096)

      while (bytes_read = upload_io.read(buffer)) > 0
        buffer[0, bytes_read]
      end

      upload_io.uploaded.should eq 8192
      uploaded_total.should eq 8192
      chunks.should eq [4096, 4096]
    end

    describe "cancel method" do
      it "stops upload after cancel is called" do
        data = Bytes.new(8192) { 1_u8 }
        uploaded_total = 0
        chunks = [] of Int32

        upload_io = UploadIO.new(
          data,
          4096,
          ->(chunk_size : Int32) {
            uploaded_total += chunk_size
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
        uploaded_total.should eq 4096
        chunks.should eq [4096]
      end

      it "closes IO source when cancelled" do
        io = IO::Memory.new("This is a streamed test.")
        uploaded_total = 0

        upload_io = UploadIO.new(
          io,
          8,
          ->(chunk_size : Int32) {
            uploaded_total += chunk_size
          }
        )

        buffer = Bytes.new(8)

        # Read first chunk
        bytes_read = upload_io.read(buffer)
        bytes_read.should eq 8

        # Cancel upload
        upload_io.cancel

        # IO should be closed
        io.closed?.should be_true

        upload_io.uploaded.should eq 8
        uploaded_total.should eq 8
      end
    end
  end
end
