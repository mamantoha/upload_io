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
  end
end
