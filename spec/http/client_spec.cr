require "../spec_helper"

describe UploadIO do
  context HTTP::Client do
    it "upload bytes" do
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
  end
end
