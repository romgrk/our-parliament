module Scrapers
  module Members
    class ParliamentExtractor
      HOST = "www.parl.gc.ca"
      PATH = ""
      QUERY_STRING = ""

      attr_reader :output_dir

      def initialize(options = {})
        @output_dir = options[:output_dir] || File.join(Rails.root, "tmp", "data")
        FileUtils.mkdir_p(@output_dir) if !File.directory?(@output_dir)
      end

      def run
        Net::HTTP.start(HOST) do |http|
          response = http.get(url)
          if response.code == "200"
            puts "Writing data to #{output_file}"
            File.open(output_file, "w") { |f| f.write(response.body) }
            puts "File written"
          else
            puts "Error: #{response.code} #{response.inspect}"
          end
        end
      end

      def output_file
        raise NotImplementedError
      end

      private

      def url
        raise NotImplementedError
      end
    end
  end
end