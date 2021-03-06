#!/usr/bin/env ruby

# == Synopsis 
#   brawsend listens on a port for blinkenpackets or requests them from a proxy and writes them in the output-file appending in the simple format <length><data> with the length being an uint16 in network byte order
# == Examples
#   blinkenpackets.rb -p 2323
#
#   Other examples:
#     ruby_cl_skeleton -n -p 2324
# == Usage 
#   brawsend.rb [-v | -h] [-l] [-f] [-a] filename [targetaddress:port | port]
#
#   For help use: brawsend.rb -h
#   default is listen locally to 2323
# == Options
#   -h, --help          Displays help message
#   -v, --version       Display the version, then exit
#   -l, --loop          Loop indefinately
#   -f, --frames        Output frame content
#   -t, --timestamp     Output 64-bit timestamp instead of human redable time
#   -a, --asciidisplay  Output frames as ascii using ' .,:;+io!4768%@$'
# == Author
#   Dominik Wagner
# == Copyright
#   Frei und so.

require 'thread'
require 'socket'
require 'ipaddr'
require 'optparse' 
require 'rdoc/ri/ri_paths'
require 'rdoc/usage'
require 'ostruct'
require 'date'


class App
  VERSION = '0.1'
  
  attr_reader :options

  def initialize(arguments, stdin)
    @arguments = arguments
    @stdin = stdin
    
    @clients = {}
    
    # Set defaults
    @options = OpenStruct.new
    @options.targetAddress = "localhost"
    @options.targetPort = 2323
    @options.heartbeatPort = 4242
    @options.showFrames = false
    @options.loops = false
    @options.filename = ""
    @semaphore = Mutex.new
  end

  # Parse options, check arguments, then process the command
  def run
        
    if parsed_options? && arguments_valid? 
      
      puts "Start at #{DateTime.now}\\n\\n" if @options.verbose

      process_arguments            
      process_command
      
      puts "\\nFinished at #{DateTime.now}" if @options.verbose
      
    else
      output_usage
    end
      
  end
  
  protected
  
    def parsed_options?
      
      # Specify options
      opts = OptionParser.new 
      opts.on('-v', '--version')    { output_version ; exit 0 }
      opts.on('-h', '--help')       { output_help ; exit 0 }
      opts.on('-l', '--loop')   { @options.loops = true }
      opts.on('-f', '--frames')   { @options.showFrames = true }
      opts.on('-t', '--timestamp')  { @options.timestamp = true }
      opts.on('-a', '--asciidisplay')  { @options.ascii = true }
      # TO DO - add additional options
            
      opts.parse!(@arguments) rescue return false
      
      process_options
      true      
    end

    # Performs post-parse processing on options
    def process_options
      @options.verbose = false if @options.quiet
    end
    
    def output_options
      puts "Options:\\n"
      
      @options.marshal_dump.each do |name, val|        
        puts "  #{name} = #{val}"
      end
    end

    # True if required arguments were provided
    def arguments_valid?
      if @arguments.length > 0
        @options.filename = @arguments[0]
      end
      if @arguments.length >= 2
        proxyAddress, proxyPort = @arguments[1].split(':')
        unless proxyPort.nil?
          @options.targetAddress = proxyAddress
          @options.targetPort = proxyPort.to_i
        else
          @options.targetPort = proxyAddress.to_i
        end
      end

      @arguments.length <= 2 && @arguments.length > 0
    end
    
    # Setup the arguments
    def process_arguments
      # TO DO - place in local vars, etc
    end
    
    def output_help
      output_version
      RDoc::usage() #exits app
    end
    
    def output_usage
      RDoc::usage('usage') # gets usage from comments above
    end
    
    def output_version
      puts "#{File.basename(__FILE__)} version #{VERSION}"
    end
    
    def send_heartbeat
      data = [0x42424242,0,0,0].pack("NnnN")
      @socket.send(data,0,@options.proxyAddress,@options.proxyPort)
      print Time.now.strftime("%Y-%m-%d %H:%M:%S") + ": -------> Sent ping to #{@options.proxyAddress} #{@options.proxyPort} \n"
      sleep(5)
    end

    
    def process_command

      asciitable = ' .,:;+io!4768%@$'
      
      @socket = UDPSocket.open
      
      print "brawsending from file #{@options.outfilename}\n"
      STDOUT.flush
      isFirstFrame = true
      lastframetime = nil
      begin # do while loop
        File.open(@options.filename,"r") do |inFile|      
          loop do
            datalength_in_bytes = inFile.read(2)
            break if datalength_in_bytes.nil?
  
            datalength,ignore = datalength_in_bytes.unpack('n')
            
            data = inFile.read(datalength)
            if data.length != datalength 
              print "-------> data was cut off! <-------"
              break
            end
            magic,ignore = data.unpack('N')
            
            
            if magic == 0x23542668
              magic,timestampBig,timestampLittle = data.unpack('NNN')
              timestamp = ((timestampBig << 32) + timestampLittle)
              timeAt = Time.at(timestamp / 1000.0);
              unless isFirstFrame
                timeDifference = (timeAt - lastframetime)
                sleep([[timeDifference, 4.0].min, 0.0].max) #never sleep for longer than 4 seconds
              else
                isFirstFrame = false
              end
              lastframetime = timeAt
              
              @socket.send(data,0,@options.targetAddress,@options.targetPort)
              
            end
            
            if @options.showFrames
              now = Time.now
              timestring = if @options.timestamp
                "0x%016x" % (now.to_f * 1000).to_i
              else
                now.strftime("%Y-%m-%d %H:%M:%S") + ".%03d" % (now.usec / 1000)
              end
              
              print "[#{timestring}]: Sending packet (#{data.length} bytes), magic: 0x#{"%08x" % magic} \n"
              print "  first 12 bytes: "
              data[0...12].each_byte {|b| print "%02x " % b }
              print "\n"
    
              if (magic == 0x23542666) 
            
            # struct mcu_frame_header
            # {
            #   int32_t magic;     /* == MAGIC_MCU_FRAME                        */
            #   int16_t height;    /* rows                                      */
            #   int16_t width;     /* columns                                   */
            #   int16_t channels;  /* Number of channels (mono/grey: 1, rgb: 3) */
            #   int16_t maxval;    /* maximum pixel value (only 8 bits used)    */
            #   /*
            #    * followed by
            #    * unsigned char data[rows][columns][channels];
            #    */
            # };
            
                magic,height,width,channels,maxval = data.unpack('Nnnnn');
                baseByte = 12
                print "          MAGIC_MCU_FRAME #{width}x#{height} channel#:#{channels} maxval:#{maxval} - content length:#{data.length-baseByte} bytes\n"
                formatString = (maxval > 15 || maxval <= 0) ? "%02x " : "%01x "
                while (height > 0) 
                  print "          "
                  if (@options.ascii)
                    data[baseByte...(baseByte + width)].each_byte { |c| print asciitable[c * (asciitable.length-1) / maxval].chr }
                  else
                    data[baseByte...(baseByte + width)].each_byte { |c| print formatString % c}
                  end
                  print "\n"
                  height = height - 1
                  baseByte = baseByte + width
                end
              elsif magic == 0x23542668
                magic,timestampBig,timestampLittle = data.unpack('NNN')
                timestamp = ((timestampBig << 32) + timestampLittle)
                timeAt = Time.at(timestamp / 1000.0);
                timestring = timeAt.strftime("%Y-%m-%d %H:%M:%S") + ".%03d" % (timeAt.usec / 1000)
                print "          MAGIC_MCU_MULTIFRAME Timestamp:0x%016x - #{timestring}\n" % [timestamp]
                
                subframeBaseByte = 12
                subframeHeaderLength = 6
                while (subframeBaseByte + subframeHeaderLength < data.length)
                
                  screenID,bpp,subHeight,subWidth = data[subframeBaseByte...subframeBaseByte + subframeHeaderLength].unpack('CCnn')
                  print "            subframe screen#:#{screenID} bpp:#{bpp} #{subWidth}x#{subHeight}\n"
      
                  if (bpp == 4)
                    byteWidth = (subWidth + 1)/2
                    formatString = "%x"
                  else
                    byteWidth = subWidth
                    formatString = "%02x "
                  end
                  
                  baseByte = subframeBaseByte + subframeHeaderLength
      
                  while subHeight > 0
                    print "            "
                    if (bpp == 4)
                      if (@options.ascii)
                        data[baseByte...(baseByte + byteWidth)].each_byte { |c| 
                          print asciitable[((c>>4) * (asciitable.length-1) / 15.0).round].chr;
                          print asciitable[((c & 0xF) * (asciitable.length-1) / 15.0).round].chr  }
                      else
                        data[baseByte...(baseByte + byteWidth)].each_byte { |c| print formatString % (c>>4) ; print formatString % (c & 0xF)}
                      end
                    else
                      if (@options.ascii)
                        data[baseByte...(baseByte + byteWidth)].each_byte { |c| 
                          print asciitable[(c * (asciitable.length-1) / 255.0).round].chr
                        }
                      else
                        data[baseByte...(baseByte + byteWidth)].each_byte { |c| print formatString % c }
                      end
                    end               
                    print "\n"
                    baseByte = baseByte + byteWidth
                    subHeight = subHeight - 1
                  end # while
                  subframeBaseByte = baseByte
                  print "\n"
                end # while 
                
              end # magicswitch
            end #showframes
          end #loop      
  
        end #File
      end while @options.loops

    rescue SignalException
      # only for easy exit
      print "\n"
    end # def

end


# Create and run the application
app = App.new(ARGV, STDIN)
app.run

