require "../spec_helper"

describe UploadIO do
  context HTTP::Client do
    it "uploads bytes" do
      url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

      data = Random::Secure.random_bytes(7_000_000).to_slice
      size = data.size

      client = HTTP::Client.new(URI.parse(url))

      headers = HTTP::Headers{
        "Content-Type"   => "application/octet-stream",
        "Content-Length" => size.to_s,
      }

      upload_io = UploadIO.new(data)
      response = client.post(url, headers: headers, body: upload_io)

      response.body.should eq("size: 7000000\n")
    end

    it "uploads a string" do
      url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

      data = "Hello, UploadIO!"
      size = data.bytesize

      client = HTTP::Client.new(URI.parse(url))

      headers = HTTP::Headers{
        "Content-Type"   => "text/plain",
        "Content-Length" => size.to_s,
      }

      upload_io = UploadIO.new(data)
      response = client.post(url, headers: headers, body: upload_io)

      response.body.should eq("size: #{size}\n")
    end

    it "uploads a file" do
      url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

      tempfile = File.tempfile("upload_test")
      size = 1_000_000
      tempfile.write(Bytes.new(size, 0x41))
      tempfile.flush
      tempfile.rewind

      client = HTTP::Client.new(URI.parse(url))

      headers = HTTP::Headers{
        "Content-Type"        => "application/octet-stream",
        "Content-Length"      => size.to_s,
        "Content-Disposition" => "attachment; filename=tempfile.bin",
      }

      upload_io = UploadIO.new(tempfile)
      response = client.post(url, headers: headers, body: upload_io)

      response.body.should eq("size: #{size}\n")

      tempfile.close
      tempfile.delete
    end

    it "uploads an empty file using Tempfile" do
      url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

      tempfile = File.tempfile("upload_test")
      size = tempfile.size

      client = HTTP::Client.new(URI.parse(url))

      headers = HTTP::Headers{
        "Content-Type"        => "text/plain",
        "Content-Length"      => size.to_s,
        "Content-Disposition" => "attachment; filename=empty_file.txt",
      }

      upload_io = UploadIO.new(tempfile)
      response = client.post(url, headers: headers, body: upload_io)

      response.body.should eq("size: 0\n")

      tempfile.close
      tempfile.delete
    end

    it "uploads nil (should do nothing)" do
      url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

      client = HTTP::Client.new(URI.parse(url))

      headers = HTTP::Headers{
        "Content-Type"   => "application/octet-stream",
        "Content-Length" => "0",
      }

      upload_io = UploadIO.new(nil)
      response = client.post(url, headers: headers, body: upload_io)

      response.body.should eq("size: 0\n")
    end

    describe "callback" do
      it "triggers callback correctly during upload" do
        url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}"

        data = Random::Secure.random_bytes(1024 * 16 + 10) # 16KB + 10 bytes
        chunk_size = 4096
        size = data.size

        received_chunks = [] of Int32
        uploaded_total = 0

        callback = ->(uploaded_chunk : Int32) {
          uploaded_total += uploaded_chunk
          received_chunks << uploaded_chunk
        }

        client = HTTP::Client.new(URI.parse(url))

        headers = HTTP::Headers{
          "Content-Type"   => "application/octet-stream",
          "Content-Length" => size.to_s,
        }

        upload_io = UploadIO.new(data, chunk_size, callback)
        response = client.post(url, headers: headers, body: upload_io)

        response.body.should eq("size: #{size}\n")

        uploaded_total.should eq size
        # Expect 4 chunks of 4096 bytes and 10 bytes
        received_chunks.should eq [chunk_size, chunk_size, chunk_size, chunk_size, 10]
      end
    end
  end
end
