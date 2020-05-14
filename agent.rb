require 'bundler/setup'
require 'sinatra'
require 'thin'
require 'builder'
require 'nokogiri'
require_relative './renderer'

class MyThinBackend < ::Thin::Backends::TcpServer
  def initialize(host, port, options)
    super(host, port)
    @ssl = true
    @ssl_options = options
  end
end

configure do
  set :environment, :production
  set :bind, '0.0.0.0'
  set :port, 41951
  set :server, "thin"
  class << settings
    def server_settings
      {
        :backend          => MyThinBackend,
        :private_key_file => File.dirname(__FILE__) + "/ca.key",
        :cert_chain_file  => File.dirname(__FILE__) + "/ca.crt",
        :verify_peer      => false
      }
    end
  end
end

get '/' do
  'dymo-printer-agent is running!'
end

get '/DYMO/DLS/Printing/StatusConnected' do
  content_type 'application/json'
  headers 'Access-Control-Allow-Origin' => '*'
  'true'
end

get '/DYMO/DLS/Printing/GetPrinters' do
  builder = Builder::XmlMarkup.new
  builder.instruct! :xml, version: '1.0', encoding: 'utf-8'
  xml = builder.Printers do |printers|
    `lpstat -s`.each_line do |line|
      next unless line =~ /device for ([^:]+)/
      name = $1
      next unless name =~ /dymo/i
      printers.LabelWriterPrinter do |printer|
        printer.Name(name)
        case line
        when /450.*turbo/i
          printer.ModelName('DYMO LabelWriter 450 Turbo')
        else
          printer.ModelName('DYMO LabelWriter 450')
        end
        printer.IsConnected('True')
        printer.IsLocal('True')
        printer.IsTwinTurbo('False')
      end
    end
  end
  content_type 'text/xml'
  headers 'Access-Control-Allow-Origin' => '*'
  xml.to_s
end

post '/DYMO/DLS/Printing/PrintLabel' do
  label_xml = params[:labelXml]
  renderer = Renderer.new(xml: label_xml, params:  {"name" => "print_this"})
  result = renderer.render
  path = File.expand_path('out.pdf', __dir__)
  File.write(path, result)

  # media = "Custom.#{renderer.pdf_width}x#{renderer.pdf_height}"
  # ,
  #   '-o', "media=#{media}"
  command = [
    'lpr',
    '-P', params[:printerName],
    '-o', 'Landscape'
  ]
  if renderer.has_graphics?
    command += ['-o', 'Resolution=300x600dpi']
    command += ['-o', 'DymoPrintQuality=Graphics']
  end
  command << path
  IO.popen(command) do |io|
    puts io.read
  end
  content_type 'application/json'
  headers 'Access-Control-Allow-Origin' => '*'
  'true'
end

