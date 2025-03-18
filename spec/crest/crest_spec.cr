require "../spec_helper"
require "crest"

describe Crest do
  upload_url = "http://#{SERVER_ADDRESS}:#{SERVER_PORT}/upload"

  it "uploads" do
    data = Random::Secure.random_bytes(7_000_000).to_slice

    upload_io = UploadIO.new(data)
    response = Crest.post(upload_url, form: upload_io)

    response.body.should eq("size: 7000000\n")
  end

  it "triggers callback during upload" do
    data = Random::Secure.random_bytes(1024 * 16 + 10) # 16KB + 10 bytes
    chunk_size = 4096
    size = data.size

    received_chunks = [] of Int32
    uploaded_total = 0

    callback = ->(uploaded_chunk : Int32) {
      uploaded_total += uploaded_chunk
      received_chunks << uploaded_chunk
    }

    upload_io = UploadIO.new(data, chunk_size, callback)
    response = Crest.post(upload_url, form: upload_io)

    response.body.should eq("size: #{size}\n")

    uploaded_total.should eq size
    # Expect 4 chunks of 4096 bytes and 10 bytes
    received_chunks.should eq [chunk_size, chunk_size, chunk_size, chunk_size, 10]
  end

  it "handle errors" do
    data = Random::Secure.random_bytes(100).to_slice

    upload_io = UploadIO.new(data)

    expect_raises Crest::RequestFailed, "HTTP status code 404: Not Found" do
      response = Crest.post("http://#{SERVER_ADDRESS}:#{SERVER_PORT}/", form: upload_io)
    end
  end
end
