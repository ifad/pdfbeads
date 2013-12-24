# encoding: UTF-8

######################################################################
#
# ImageInspector -- a simple pure Ruby module to detect basic image
# properties, such as width, height, color space or resolution. It also
# gives an access to TIFF tags and EXIF properties.
#
# Version 1.0
#
# Copyright (C) 2010 Alexey Kryukov (amkryukov@gmail.com).
# All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#######################################################################

require 'stringio'

class String
  # Protect strings which are supposed be treated as a raw sequence of bytes.
  # This is important for Ruby 1.9. For earlier versions the method just
  # does nothing.
  unless self.method_defined? :to_binary
    def to_binary()
      force_encoding 'ASCII-8BIT' if respond_to? :force_encoding
      return self
    end
  end
end

module ImageInspector
  def ImageInspector.new( input=nil )
    insp = Image.new( input )
    insp
  end
end

# Parse image header and retrieve its basic properties. The code is inspired
# by Sam Stephenson's snippet which demonstrates how to determine a JPEG 
# image size ( see http://snippets.dzone.com/posts/show/805) and Paul
# Schreiber's code for TIFF (see
# http://paulschreiber.com/blog/2010/06/10/tiff-file-dimensions-in-ruby/)
#
# Supported formats are: TIFF, PNG, JPEG and JPEG2000.
#
class ImageInspector::Image
  # Return the obvious.
  attr_reader :width, :height
  # Return image resolution (always in pixels per inch, even if it is
  # differently specified in the source image).
  attr_reader :x_dpi, :y_dpi
  # Image depth, color space, palette (for indexed images) and transparency data (for PNG)
  attr_reader :depth, :cspace, :palette, :trans
  # Image format and compression method
  attr_reader :format, :compression
  # Return TIFF tags as a hash for TIFF images or JPEG images with EXIF
  # data. Otherwise this property is nil. 
  attr_reader :tags

  @@gc = (IO.method_defined? :getbyte) ? (:getbyte) : (:getc)

  # Set all image attributes to nil and open an image if an optional 
  # argument is specified.
  def initialize( input=nil )
    clearData()
    open( input ) unless input.nil?
  end

  # Accepts either a file name or a stream-like object.
  def open( input )
    @input = input

    begin
      if input.kind_of? IO or input.kind_of? StringIO
        @fname = '<STREAM>'
        byFormat( input )
      else
        @fname = input
        File.open( input, 'rb' ) { |io| byFormat( io ) }
      end

    rescue Exception => e
      $stderr.puts( "Could not read data from #{@fname}: " << e.message )
      clearData()
      @input = nil
    end
  end

  # Return image data (possibly compressed) for a previously initialized 
  # image as a sring. For JPEG and JPEG2000 this would be the whole image
  # as it is stored on the disk, while for TIFF and PNG all headers are
  # stripped and a raw data stream is returned.
  def getRawData()
    raise "The image has not been properly initialized" if @width.nil? or @input.nil?

    begin
      if @input.kind_of? IO or @input.kind_of? StringIO
        ret = concatDataBlocks( @input )
      else
        File.open( @input, 'rb' ) { |io| ret = concatDataBlocks( io ) }
      end
      return ret
    rescue Exception => e
      $stderr.puts( "Could not read data from #{@fname}: " << e.message )
    end
  end

  def nextImage()
    if @format.eql? :TIFF and @next_off > 0
      begin
        if @input.kind_of? IO or @input.kind_of? StringIO
          tiffNext( @input )
        else
          File.open( @input, 'rb' ) { |io| tiffNext( io ) }
        end
        return true
      rescue Exception => e
        $stderr.puts( "Could not read data from #{@fname}: " << e.message )
      end
    end
    false
  end

  private

  def clearData
    @width = @height = nil
    @x_dpi = @y_dpi = 72
    @data_blocks = Array.new()
    @depth = @cspace = @palette = @trans = nil
    @compression = @format = @tags = nil
    @stream = @fname = @next_off = nil
  end

  def concatDataBlocks( io )
    io.set_encoding 'ASCII-8BIT' if io.respond_to? :set_encoding
    ret = ''

    # For JPEG/JPEG2000 just return the whole file
    if @format.eql? :JPEG or @format.eql? :JPEG2000
      ret = io.read
    # For TIFF/PNG extract raw data blocks from the image
    else
      @data_blocks.each do |b|
        io.seek( b[0],IO::SEEK_SET )
        chunk = io.read( b[1] )
        ret << chunk
      end
    end
    return ret
  end

  def byFormat( io )
    io.set_encoding 'ASCII-8BIT' if io.respond_to? :set_encoding

    sign = io.read( 2 )
    if sign.eql? "\xFF\xD8".to_binary
      @format = :JPEG
      @compression = :DCTDecode 
      jpgExamine( io )
      return
    end

    sign << io.read( 2 )
    if sign.eql? "MM\x00\x2a".to_binary or sign.eql? "II\x2a\x00".to_binary
      @format = :TIFF
      tiffExamine( io,sign )
      return
    end

    sign << io.read( 4 )
    if sign.eql? "\x89PNG\x0D\x0A\x1A\x0A".to_binary
      @format = :PNG
      pngExamine( io )
      return
    end

    sign << io.read( 4 )
    if sign.eql? "\x00\x00\x00\x0CjP  \x0D\x0A\x87\x0A".to_binary
      @format = :JPEG2000
      @compression = :JPXDecode 
      j2kParseBox( io )
      return
    end

    raise "File format not recognized"
  end

  def tiffReadArray( io,intgr,fmt,cnt,val )
    ret = []
    case fmt
      when 'C', 'c'
        rec_len = 1
      when intgr
        rec_len = 2
      when intgr.upcase
        rec_len = 4
      when intgr.upcase*2
        rec_len = 8
      when 'A*'
        rec_len = cnt
        cnt = 1
    end

    if rec_len*cnt > 4
      ptr = val.unpack( intgr.upcase )[0]
      cur_pos = io.tell
      io.seek( ptr,IO::SEEK_SET )

      for i in ( 0...cnt )
        if fmt.eql? intgr.upcase*2
          rat = io.read( rec_len ).unpack( fmt )
          ret << rat[0]/rat[1]
        else
          ret << io.read( rec_len ).unpack( fmt )[0]
        end
      end
      io.seek( cur_pos,IO::SEEK_SET )

    else
      ret = val.unpack( fmt*cnt )
    end

    return ret
  end

  def tiffNext( io )
    sign = io.read( 4 )
    tiffExamine( io,sign,@next_off )
  end

  def tiffParseIFD( io,offset,intgr )
    packspec = [
      nil,              # nothing (shouldn't happen)
      'C',              # BYTE (8-bit unsigned integer)
      'A*',             # ASCII
      intgr,            # SHORT (16-bit unsigned integer)
      intgr.upcase,     # LONG (32-bit unsigned integer)
      intgr.upcase * 2, # RATIONAL (numerator + denominator)
      'c',              # SBYTE (8-bit signed integer)
      'A*',             # undefined, but used for EXIF version
      intgr,            # SSHORT (16-bit signed integer)
      intgr.upcase,     # SLONG (32-bit signed integer)
      intgr.upcase * 2, # SRATIONAL (numerator + denominator)
    ]
    io.seek( offset,IO::SEEK_SET )
    num_dirent = io.read( 2 ).unpack( intgr )[0]

    tags = Hash.new()
    for i in ( 0...num_dirent )
      code, type, length = io.read( 8 ).unpack( "#{intgr}#{intgr}#{intgr.upcase}" )
      raise 'malformed TIFF: could not read an IFD entry' if (
        type.nil? or type > packspec.size or packspec[type].nil? )
      sval = io.read( 4 )

      tags[code] = tiffReadArray( io,intgr,packspec[type],length,sval )
    end

    @next_off = io.read( 4 ).unpack( intgr.upcase )[0]
    return tags
  end

  def tiffExamine( io,sign,offset=nil )
    if sign.eql? "MM\x00\x2a".to_binary
      intgr = 'n'
    elsif sign.eql? "II\x2a\x00".to_binary
      intgr = 'v'
    else
      raise 'malformed TIFF: no TIFF signature'
    end

    # Get offset to IFD
    offset = io.read( 4 ).unpack( intgr.upcase )[0] if offset.nil?
    @tags = tiffParseIFD( io,offset,intgr )

    # We should not expect to find required image properties (such as width
    # or height) in EXIF data of a JPEG image.
    raise 'malformed TIFF: a required tag is missing' unless @format.eql? :JPEG or ( 
      @tags.has_key? 0x0100 and @tags.has_key? 0x0101 and 
      @tags.has_key? 0x0106 and @tags.has_key? 0x0111 and @tags.has_key? 0x0117 )

    unless @format.eql? :JPEG
      @width = @tags[0x0100][0]; @height = @tags[0x0101][0]

      @tags[0x0111].each_index do |i|
        @data_blocks << [ @tags[0x0111][i],@tags[0x0117][i] ]
      end

      case @tags[0x0106][0]
        when 0, 1
          @cspace = :DeviceGray
        when 3
          @cspace = :Indexed
        when 5
          @cspace = :DeviceCMYK
        else
          @cspace = :DeviceRGB
      end

      if @tags[0x0106][0] == 3 and @tags.has_key? 0x0140
        @palette = Array.new()
        clen = @tags[0x0140].length / 3
        for i in ( 0...clen )
          r = @tags[0x0140][i]
          g = @tags[0x0140][i+clen]
          b = @tags[0x0140][i+clen*2]
          @palette << [ r/256,g/256,b/256 ]
        end
      end
      @depth = 1
      @depth = @tags[0x0102][0] if @tags.has_key? 0x0102
    end
    @tags.merge! tiffParseIFD( io,@tags[0x8769][0],intgr ) if @tags.has_key? 0x8769

    if @tags.has_key? 0x0103
      case @tags[0x0103][0]
        when 1
          @compression = :NoCompression
        when 3, 4
          @compression = :CCITTFaxDecode
        when 5
          @compression = :LZWDecode
        when 8, 32946
          @compression = :FlateDecode
      end
    end

    if ( @tags.has_key? 0x011A and @tags.has_key? 0x011B )
      @x_dpi = @tags[0x011A][0]; @y_dpi = @tags[0x011B][0]
      if @tags.has_key? 0x0128 and @tags[0x0128][0] == 3
        @x_dpi = (@x_dpi * 2.54).round
        @y_dpi = (@y_dpi * 2.54).round
      end
    end
  end

  def j2kParseBox( io )
    buf = [ 0 ] * 8
    while b = io.send( @@gc )
      # always keep last 8 bytes so that we can check for chunk name and length
      buf.shift
      buf.push( b )
      tag = buf[4..7].pack('c*')

      # Currently no support for resolution, as I have never seen JP2 images
      # with 'res '/'resc'/'resd' boxes, and not sure if they are ever used.
      if ['ftyp','jp2h','ihdr','colr','res ','resc',
          'resd','prfl','bpcc','pclr','cdef','jp2i'].include? tag
        length = buf[0..4].pack( 'c*' ).unpack( 'N' )[0]
        if length == 0
          length = io.read( 8 ).unpack( 'N' )[0]
          length -= 8
        end
        length -= 8
        case tag
          when 'jp2h'
            iostr = StringIO.new( io.read( length ))
            j2kParseBox( iostr )
            return
          when 'ihdr'
            if length == 14
              @height  = io.read( 4 ).unpack( 'N' )[0]
              @width   = io.read( 4 ).unpack( 'N' )[0]
              ncomps   = io.read( 2 ).unpack( 'n' )[0]
              strdepth = io.read( 1 )
              signed   = !(strdepth.unpack( 'C' )[0] >> 7).zero?
              fmt = signed ? 'c' : 'C'
              @depth = (strdepth.unpack( fmt )[0] & 0x7f) + 1
            else
              raise 'Malformed JPEG2000: the file is damaged or has an unsupported format'
            end
          when 'colr'
            next unless @cspace.nil?
            meth, prec, approx = io.read( 3 ).unpack( 'CcC' )
            if meth == 1
              enumcs = io.read( 4 ).unpack( 'N' )[0]
              case enumcs
                when 16
                  @cspace = :DeviceRGB
                when 17
                  @cspace = :DeviceGray
                else
                  raise 'Malformed JPEG2000: unknown colorspace'
              end
            end
            return
          else
            io.read( length )
        end
      end
    end
  end

  def pngExamine( io )
    io.seek( 16,IO::SEEK_SET )
    @width, @height, @depth, color, compr, filtr, interlace  = io.read( 13 ).unpack('NNccccc')
    @compression = :FlateDecode if compr == 0 and filtr == 0
    case color
      when 0, 4
        @cspace = :DeviceGray
      when 3
        @cspace = :Indexed
      else
        @cspace = :DeviceRGB
    end

    buf = [ 0 ] * 8
    ctags = [ 'IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'cHRM',
              'gAMA', 'iCCP', 'sBIT', 'sRGB', 'iTXt', 'tEXt',
              'zTXt', 'bKGD', 'hIST', 'pHYs', 'sPLT', 'tIME' ]
    while b = io.send( @@gc )
      # always keep last 8 bytes so that we can check for chunk name and length
      buf.shift
      buf.push( b )
      tag = buf[4..7].pack('c*')

      if ctags.include? tag
        length = buf[0..4].pack( 'c*' ).unpack( 'N' )[0]
        case tag
          when 'PLTE'
            @palette = Array.new()
            for i in (0...length/3)
              r, g, b = io.read( 3 ).unpack( 'CCC' )
              @palette << [ r, g, b ]
            end
          when 'IDAT'
            @data_blocks << [ io.tell,length ]
            io.seek( length + 4,IO::SEEK_CUR )
          when 'pHYs'
            x_dpm, y_dpm = io.read( 8 ).unpack( 'NN' )
            @x_dpi = (x_dpm/100 * 2.54).round
            @y_dpi = (y_dpm/100 * 2.54).round
          when 'tRNS'
            trans = Hash.new()
            case @cspace
              when :Indexed
                # Indexed colour, RGB. Each byte in this chunk is an alpha for
                # the palette index in the PLTE ("palette") chunk up until the
                # last non-opaque entry. Set up an array, stretching over all
                # palette entries which will be 0 (opaque) or 1 (transparent).
                @trans = io.read( length ).unpack( 'C*' )
              when :DeviceGray
                # Greyscale. Corresponding to entries in the PLTE chunk.
                # Grey is two bytes, range 0 .. (2 ^ bit-depth) - 1
                @trans = io.read( 2 ).unpack( 'n' )
              when :DeviceRGB
                # True colour with proper alpha channel.
                @trans = io.read( 6 ).unpack( 'nnn' )
            end
          when 'IEND'
            break
          else
            io.seek( length + 4,IO::SEEK_CUR )
        end
      end
    end
  end

  def jpgNextMarker( io )
    c = io.send( @@gc ) until c == 0xFF
    c = io.send( @@gc ) while c == 0xFF
    c
  end

  def jpgReadFrame( io )
    off = io.read( 2 ).unpack( 'n' )[0]
    io.read( off - 2 )
  end

  def jpgExamine( io )
    while marker = jpgNextMarker( io )
      case marker
        # SOF markers
        when 0xC0..0xC3, 0xC5..0xC7, 0xC9..0xCB, 0xCD..0xCF
          length, @depth, @height, @width, components = io.read( 8 ).unpack( 'ncnnc' )
          raise 'malformed JPEG: could not read a SOF header' unless length == 8 + components * 3
          case components
            when 1
              @cspace = :DeviceGray
            when 4
              @cspace = :DeviceCMYK
            else
              @cspace = :DeviceRGB
          end
        # EOI, SOS
        when 0xD9, 0xDA
          break
        # APP0, contains JFIF tag
        when 0xE0
          length,sign,version,units,@x_dpi,@y_dpi = io.read( 14 ).unpack( 'nZ5ncnn' )
          raise 'malformed JPEG: could not read JFIF data' unless length == 16 and sign.eql? 'JFIF'
          if units == 2
            @x_dpi = (@x_dpi * 2.54).round
            @y_dpi = (@y_dpi * 2.54).round
          end
        # APP1, contains EXIF tag
        when 0xE1
          exif = jpgReadFrame( io )
          exif_hdr = exif[0...6]
          if exif_hdr.eql? "Exif\x00\x00".to_binary
            buf = StringIO.new( exif[6..-1] )
            sign = buf.read( 4 )
            tiffExamine( buf,sign )
          end
        # ignore frame
        else
          jpgReadFrame( io )
      end
    end
  end
end
