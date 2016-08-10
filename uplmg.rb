#!/usr/bin/env ruby
# conding: utf-8

require 'optparse'
require 'net/https'
require 'net/http/post/multipart'

# -------------------------------------------------------
# Uplmg - doc
# https://doc.uplmg.com/
# -------------------------------------------------------
# net/http - examples:
# http://www.rubyinside.com/nethttp-cheat-sheet-2940.html
# https://github.com/nicksieger/multipart-post
# -------------------------------------------------------
class UpImg
  OFFICIAL_ENDPOINT = 'https://uplmg.com'

  attr_writer :sender

  def self.endpoint(url)
    uri = URI(url)
    @api = Net::HTTP.new(uri.host, uri.port)
    @api.use_ssl = uri.port == 443
    @api.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  def self.get(id, output = nil, limit = 5)
    return "#{id}: Too many HTTP redirects" if limit == 0

    request = Net::HTTP::Get.new("/#{id}")
    response = @api.request(request)

    case response
    when Net::HTTPSuccess then
      filename = (response['content-disposition'].match(/filename=(\"?)(.+)\1/)[2] rescue id)
      filename = id if filename.empty?

      File.write(output || filename, response.body)
    when Net::HTTPRedirection then
      location = response['location']
      endpoint(location)
      warn "#{id}: Redirected to #{location}"
      return get(id, output, limit - 1)
    end

    response
  end

  def self.upload(filename, output = nil, limit = 5)
    basename = File.basename(filename)

    return "#{basename}: Too many HTTP redirects" if limit == 0

    request = Net::HTTP::Post::Multipart.new('/file/upload', senderid: @sender || 'ruby-cli', file: UploadIO.new(File.new(filename), '', output || basename))
    response = @api.request(request)

    case response
    when Net::HTTPRedirection then
      location = response['location']
      endpoint(location)
      warn "#{basename}: Redirected to #{location}"
      return upload(filename, output, limit - 1)
    end

    response
  end
end

endpoint = UpImg::OFFICIAL_ENDPOINT

opt_parser = OptionParser.new do |opt|
  opt.banner = 'Usage:'
  opt.separator  'uplmg [OPTIONS] [FILE ...]'
  opt.separator  'upimg [OPTIONS] [URL ...]'
  opt.separator  'upimg [OPTIONS] [SHORTNAME ...]'
  opt.separator  ''
  opt.separator  'Options'

  opt.on('-s', '--sender SENDER', 'set sender name') do |sender|
    UpImg.sender = sender
  end

  opt.on('-e', '--endpoint ENDPOINT', 'set endpoint') do |url|
    endpoint = url
  end

  opt.on('-h', '--help', 'help') do
    puts opt_parser
  end
end

opt_parser.parse!

unless ARGV.empty?
  ARGV.each do |arg|
    separator = arg.index('=') || 0
    filename = arg[0..(separator - 1)]
    output = arg[(separator + 1)..-1] unless separator.zero?

    if (matched = filename.match(/^https?:\/\/uplmg.com\/(\w+)$/))
      UpImg.endpoint(filename)
      response = UpImg.get(matched[1], output)

      case response
      when Net::HTTPNotFound then
        warn "#{matched[1]}: File not found"
      end
    else
      if File.exists?(filename)
        UpImg.endpoint(endpoint)
        response = UpImg.upload(filename, output)

        case response
        when Net::HTTPSuccess then
          puts "#{filename}: #{response.body}"
        else
          warn "#{filename}: Internal error"
        end
      else
        UpImg.endpoint(endpoint)
        response = UpImg.get(filename, output) if (/^\w+$/ =~ filename) == 0

        case response
        when Net::HTTPNotFound, nil then
          warn "#{File.basename(filename)}: File not found"
        end
      end
    end
  end
else
  puts opt_parser
end
