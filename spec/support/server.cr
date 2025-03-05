require "mime"
require "http/server"

class Server
  CONTENT_DISPOSITION_FILENAME_REGEX = /filename\*?=['"]?(?:UTF-\d['"]*)?([^;\r\n"']*)['"]?;?/xi
  UPLOAD_DIR                         = "#{__DIR__}/uploads"

  def self.run(address = "127.0.0.1", port = 9909)
    Dir.mkdir_p(UPLOAD_DIR)

    server = HTTP::Server.new do |context|
      request = context.request
      response = context.response

      if request.method == "POST"
        request_content_type = request.headers["Content-Type"]?
        content_disposition = request.headers["Content-Disposition"]?

        filename =
          if content_disposition && (match_data = content_disposition.match(CONTENT_DISPOSITION_FILENAME_REGEX))
            match_data[1]
          else
            suffix = request_content_type ? MIME.extensions(request_content_type).first? || "bin" : "bin"
            "uploaded_file.#{suffix}"
          end

        path = File.join(UPLOAD_DIR, filename)

        file_size = 0
        File.open(path, "w") do |file|
          request.body.try do |body|
            file_size = IO.copy(body, file)
          end
        end

        response.status = HTTP::Status::OK
        response.puts "size: #{file_size}"
      else
        response.status = HTTP::Status::METHOD_NOT_ALLOWED
        response.puts "Method Not Allowed"
      end
    end

    puts "Server running at http://#{address}:#{port}"
    server.bind_tcp(address, port)
    server.listen
  end
end
