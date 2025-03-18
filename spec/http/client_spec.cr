require "../spec_helper"

describe UploadIO do
  context HTTP::Client do
    upload_url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}/upload"

    it "uploads bytes" do
      data = Random::Secure.random_bytes(7_000_000).to_slice
      size = data.size

      headers = HTTP::Headers{
        "Content-Type"   => "application/octet-stream",
        "Content-Length" => size.to_s,
      }

      upload_io = UploadIO.new(data)
      response = HTTP::Client.post(upload_url, headers: headers, body: upload_io)

      response.body.should eq("size: 7000000\n")
    end

    it "uploads a string" do
      data = "Hello, UploadIO!"
      size = data.bytesize

      headers = HTTP::Headers{
        "Content-Type"   => "text/plain",
        "Content-Length" => size.to_s,
      }

      upload_io = UploadIO.new(data)
      response = HTTP::Client.post(upload_url, headers: headers, body: upload_io)

      response.body.should eq("size: #{size}\n")
    end

    it "uploads a file" do
      tempfile = File.tempfile("upload_test")
      size = 1_000_000
      tempfile.write(Bytes.new(size, 0x41))
      tempfile.flush
      tempfile.rewind

      headers = HTTP::Headers{
        "Content-Type"        => "application/octet-stream",
        "Content-Length"      => size.to_s,
        "Content-Disposition" => "attachment; filename=tempfile.bin",
      }

      upload_io = UploadIO.new(tempfile)
      response = HTTP::Client.post(upload_url, headers: headers, body: upload_io)

      response.body.should eq("size: #{size}\n")

      tempfile.close
      tempfile.delete
    end

    it "uploads an empty file using Tempfile" do
      tempfile = File.tempfile("upload_test")
      size = tempfile.size

      headers = HTTP::Headers{
        "Content-Type"        => "text/plain",
        "Content-Length"      => size.to_s,
        "Content-Disposition" => "attachment; filename=empty_file.txt",
      }

      upload_io = UploadIO.new(tempfile)
      response = HTTP::Client.post(upload_url, headers: headers, body: upload_io)

      response.body.should eq("size: 0\n")

      tempfile.close
      tempfile.delete
    end

    it "uploads nil (should do nothing)" do
      headers = HTTP::Headers{
        "Content-Type"   => "application/octet-stream",
        "Content-Length" => "0",
      }

      upload_io = UploadIO.new(nil)
      response = HTTP::Client.post(upload_url, headers: headers, body: upload_io)

      response.body.should eq("size: 0\n")
    end

    it "handle errors" do
      data = Random::Secure.random_bytes(100).to_slice

      upload_io = UploadIO.new(data)
      response = HTTP::Client.post("http://#{SERVER_ADDRESS}:#{SERVER_PORT}/", body: upload_io)

      response.status_code.should eq(404)
    end

    describe "callback" do
      it "triggers callback correctly during upload" do
        data = Random::Secure.random_bytes(1024 * 16 + 10) # 16KB + 10 bytes
        chunk_size = 4096
        size = data.size

        received_chunks = [] of Int32
        uploaded_total = 0

        callback = ->(uploaded_chunk : Int32) {
          uploaded_total += uploaded_chunk
          received_chunks << uploaded_chunk
        }

        headers = HTTP::Headers{
          "Content-Type"   => "application/octet-stream",
          "Content-Length" => size.to_s,
        }

        upload_io = UploadIO.new(data, chunk_size, callback)
        response = HTTP::Client.post(upload_url, headers: headers, body: upload_io)

        response.body.should eq("size: #{size}\n")

        uploaded_total.should eq size
        # Expect 4 chunks of 4096 bytes and 10 bytes
        received_chunks.should eq [chunk_size, chunk_size, chunk_size, chunk_size, 10]
      end
    end
  end
end
