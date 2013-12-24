# encoding: UTF-8

######################################################################
#
# PDFBeads -- convert scanned images to a single PDF file
# Version 1.0
#
# Unlike other PDF creation tools, this utility attempts to implement
# the approach typically used for DjVu books. Its key feature is
# separating scanned text (typically black, but indexed images with
# a small number of colors are also accepted) from halftone images 
# placed into a background layer.
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

# Represents a set of page images accompanies with auxiliary files
# needed to build a PDF document.
class PDFBeads::PageDataProvider < Array

  # Allows to collect data needed for building an individual page
  # of a PDF document and gives access to those data.
  class PageData
    attr_reader :name, :basename, :s_type, :stencils, :hocr_path, :fg_created, :bg_created
    attr_accessor :width, :height, :x_res, :y_res, :fg_layer, :bg_layer

    def initialize( path,basename,args,exts,pref )
      @name = path
      @basename = basename
      @s_type = 'b'
      @stencils = Array.new()
      @pageargs = args
      @exts = exts
      @pref = pref
      @bg_layer = @fg_layer = nil
      @bg_created = @fg_created = false
    end

    def fillStencilArray()
      ret   = 0
      force = @pageargs[:force_update]
      fres  = @pageargs[:st_resolution]
      treshold = @pageargs[:threshold]

      map = Hash[
        :path => @name,
        :rgb  => [0.0, 0.0, 0.0],
        :created => false
      ]

      insp = ImageInspector.new( @name )
      return 0 if insp.width.nil?

      @width = insp.width; @height = insp.height
      unless fres > 0
        @x_res = insp.x_dpi; @y_res = insp.y_dpi
      else
        @x_res = @y_res = fres
      end

      if insp.depth == 1 and insp.trans.nil?
        @stencils << map
        ret = 1

      else
        img = ImageList.new( @name )
        # ImageMagick incorrectly identifies indexed PNG images as DirectClass.
        # It also assigns a strange color value to fully opaque areas. So
        # we have to use an independent approach to recognize indexed images.
        unless insp.palette.nil?
          img.class_type = PseudoClass
          ret = processIndexed( img,@pageargs[:maxcolors],force )
        end
        ret = processMixed( img,treshold,force,map ) if ret == 0
        img.destroy!

        # Make sure there are no more RMagick objects
        GC.start
      end

      $stderr.puts( "Prepared data for processing #{@name}\n" )
      if insp.nextImage
        $stderr.puts( "Warning: #{@name} contains multiple images, but only the first one") 
        $stderr.puts( "\tis going to be used\n" )
      end
      ret
    end

    def addSupplementaryFiles()
      force = @pageargs[:force_update]
      exts_pattern = @exts.join( '|' )
      pref_pattern = @pref.join( '|' )

      if @bg_layer.nil?
        bgpath = Dir.entries('.').detect do |f|
          /\A#{@basename}.(bg|sep).(#{pref_pattern})\Z/i.match(f)
        end
        bgpath = Dir.entries('.').detect do |f|
          /\A#{@basename}.(bg|sep).(#{exts_pattern})\Z/i.match(f)
        end if bgpath.nil?
        @bg_layer = bgpath unless bgpath.nil?

        # If updating auxiliary files is requested and the base image is
        # either monochrome or indexed with just a few colors (i. e. doesn't
        # contain any elements which should be encoded to the background layer),
        # then the *.color.* image (if present) takes priority over any existing
        # *.bg.* and *.fg.* images. So we should regenerate them.
        if bgpath.nil? or ( force and not @s_type.eql? 'c' )
          colorpath = Dir.entries('.').detect do |f|
            /\A#{@basename}.color.(#{exts_pattern})\Z/i.match(f)
          end
          unless colorpath.nil?
            fnames = Array.new()
            separateColor( colorpath )
          end
        end
      end

      if @fg_layer.nil? and @stencils.length == 1
        fgpath = Dir.entries('.').detect do |f|
          /\A#{@basename}.(fg).(#{exts_pattern})\Z/i.match(f)
        end
        @fg_layer = fgpath unless fgpath.nil?
      end

      if $has_hpricot
        @hocr_path = Dir.entries('.').detect do |f|
          /\A#{@basename}.(HOCR|HTML?)/i.match(f)
        end
      end
    end

    def self.fixResolution( img )
      xres = img.x_resolution; yres = img.y_resolution
      if img.units == PixelsPerCentimeterResolution
        img.units = PixelsPerInchResolution
        xres = (xres * 2.54).round
        yres = (yres * 2.54).round
      end
      return [ xres, yres ]
    end

    private

    def writeImage( img,path,fmt )
      begin
        img.write( path ) do
          case fmt
          when 'JP2'
            self.define( 'JP2','mode','real' )
            self.define( 'JP2','numrlvls',4 )
            self.define( 'JP2','rate',0.015625 )
          when 'JPG'
            self.quality = 50
          else
            self.compression = ZipCompression
            self.quality = 95
          end
          self.format = fmt
        end
        return true
      rescue
        $stderr.puts( "Error: could not write to #{path}" )
        return false
      end
    end

    def processIndexed( img,maxcolors,force )
      ret = 0
      ncolors = img.number_colors
      if ncolors <= maxcolors
        @s_type = 'i'
        exc = ( img.alpha? ) ? '#00000000' : 'white'
        for i in ( 0...ncolors )
          color = img.colormap( i )
          px = Pixel.from_color( color )
          unless color.eql? exc
            cpath = "#{@basename}.#{color}.tiff"
            created = false
            if not File.exists? cpath or force
              bitonal = img.copy
              # Caution: replacing colors in the colormap currently only works
              # if we save the result into a bilevel TIFF file. Otherwise the
              # changes are ignored or produce a strange effect. We still use
              # this method because it allows to reduce the number of memory
              # allocations.
              for j in (0...ncolors)
                crepl = (j == i) ? 'black' : 'white'
                bitonal.colormap( j,crepl )
              end
              bitonal.compress_colormap!
              bitonal.write( cpath ) do
                self.format = 'TIFF'
                self.define( 'TIFF','rows-per-strip',img.rows )
                self.compression = Group4Compression
              end
              bitonal.destroy!
              created = true
            end
            cmap = Hash[
              :path => cpath,
              :rgb  => [px.red.to_f/QuantumRange, px.green.to_f/QuantumRange, px.blue.to_f/QuantumRange],
              :created => created
            ]
            @stencils << cmap
            ret += 1
          end
        end
      end
      return ret
    end

    def processMixed( img,treshold,force,map )
      binpath = "#{@basename}.black.tiff"
      if not File.exists? binpath or force
        im_copy = img.copy; bitonal = im_copy.threshold(QuantumRange/255*treshold); im_copy.destroy!
        bitonal.write( binpath ){
          self.format = 'TIFF'
          self.define( 'TIFF','rows-per-strip',img.rows )
          self.compression = Group4Compression
        }
        bitonal.destroy!
        map[:created] = true
      end

      bgf = @pageargs[:bg_format]
      bgpath = "#{@basename}.bg." << bgf.downcase

      if not File.exists? bgpath or force
        if treshold > 1
          bk = img.black_threshold(QuantumRange/255*treshold); img.destroy!; img = bk
        end
        op = img.opaque( 'black','white' ); img.destroy!; img = op;
        if @pageargs[:force_grayscale]
          img.image_type = GrayscaleType
        end
        PageData.fixResolution( img )
        resampled = img.resample(@pageargs[:bg_resolution]); img.destroy!; img = resampled

        # A hack for some Windows versions of RMagick, which throw an error the
        # first time when Magick.formats is accessed
        begin
          retries = 2
          mfmts = Magick.formats
        rescue
          retry if (retries -= 1 ) > 0
        end
        if bgf.eql? 'JP2' and not mfmts.has_key? 'JP2'
          $stderr.puts( "This version of ImageMagick doesn't support JPEG2000 compression." )
          $stderr.puts( "\tI'll use JPEG compression instead." )
          bgf = 'JPG'
          bgpath = "#{@basename}.bg." << bgf.downcase
        end

        writeImage( img,bgpath,bgf )
        @bg_created = true
      end

      map[:path] = binpath
      @stencils << map
      @s_type= 'c'
      @bg_layer = bgpath
      ret = 1
    end

    def separateColor( colorpath )
      fmt = @pageargs[:bg_format]
      dpi = @pageargs[:bg_resolution]

      begin
        img  = ImageList.new( colorpath )
      rescue ImageMagickError
        $stderr.puts( "Error reading image file #{colorpath}" )
        return nil
      end

      begin
        mask = ImageList.new( @name )
      rescue ImageMagickError
        $stderr.puts( "Error reading image file #{@name}" )
        return nil
      end

      imw = img.columns
      imh = img.rows

      if @s_type.eql? 'i'
        mask.class_type = PseudoClass
        exc = ( mask.alpha? ) ? '#00000000' : 'white'
        for i in ( 0...mask.number_colors )
          color = mask.colormap( i )
          unless color.eql? exc
            op = mask.opaque( color,'black' )
            mask.destroy!
            mask = op
          end
        end

        if mask.alpha?
          op = mask.opaque( exc,'white' )
          mask.destroy!
          mask = op
          mask.alpha( DeactivateAlphaChannel )
        end
        mask.compress_colormap!
      end

      PageData.fixResolution( img )
      mask.resize!( imw,imh ) if mask.columns != imw or mask.rows != imh

      no_fg = img.composite( mask,CenterGravity,CopyOpacityCompositeOp )
      bg = no_fg.blur_channel( 0,6,AllChannels )
      bg.alpha( DeactivateAlphaChannel )

      bg.composite!( no_fg,CenterGravity,OverCompositeOp )
      if ( bg.x_resolution != dpi or bg.y_resolution != dpi )
        resampled = bg.resample( dpi ); bg.destroy!; bg = resampled
      end

      bgpath = "#{@basename}.bg." << fmt.downcase
      if writeImage( bg,bgpath,fmt )
        @bg_layer = bgpath
        @bg_created = true
      end

      bg.destroy!
      no_fg.destroy!

      unless @bg_layer.nil? or @s_type.eql? 'i'
        ksam = mask.negate
        mask.destroy!

        no_bg = img.composite( ksam,CenterGravity,CopyOpacityCompositeOp )
        fg = no_bg.clone

        # Resize the image to a tiny size and then back to the original size
        # to achieve the desired color diffusion. The idea is inspired by
        # Anthony Thyssen's http://www.imagemagick.org/Usage/scripts/hole_fill_shepards
        # script, which is intended just for this purpose (i. e. removing undesired
        # areas from the image). However our approach is a bit cruder (but still
        # effective).
        fg.resize!( width=imw/100,height=imh/100,filter=GaussianFilter )
        fg.resize!( width=imw,height=imh,filter=GaussianFilter )
        fg.composite!( no_bg,CenterGravity,OverCompositeOp )
        downs = fg.resample( 100 ); fg.destroy!; fg = downs
        fg.alpha( DeactivateAlphaChannel )

        fgpath = "#{@basename}.fg." << fmt.downcase
        if writeImage( fg,fgpath,fmt )
          @fg_layer = fgpath
          @fg_created = true
        end

        fg.destroy!
        no_bg.destroy!
        ksam.destroy!
      else
        mask.destroy!
      end
      img.destroy!
      # Make sure there are no more RMagick objects still residing in memory
      GC.start
    end
  end

  # Takes a list of file names and a hash containing a set of options.
  def initialize( files,args )
    @pageargs = args

    ext_lossless = [ 'PNG','TIFF?' ]
    ext_jpeg     = [ 'JPE?G' ]
    ext_jpeg2000 = [ 'JP2','JPX' ]

    @exts = Array.new()

    case @pageargs[:bg_format]
    when 'JP2'
      @exts << ext_jpeg2000 << ext_jpeg << ext_lossless
      @pref = Array.new( ext_jpeg2000 )
    when 'JPG'
      @exts << ext_jpeg << ext_jpeg2000 << ext_lossless
      @pref = Array.new( ext_jpeg )
    else
      @exts << ext_lossless << ext_jpeg2000 << ext_jpeg
      @pref = Array.new( ext_lossless )
    end

    # A hack for some Windows versions of RMagick, which throw an error the
    # first time when Magick.formats is accessed
    begin
      retries = 2
      mfmts = Magick.formats
    rescue
      retry if (retries -= 1 ) > 0
    end
    unless mfmts.has_key? 'JP2'
      @exts.delete_if{ |ext| ext_jpeg2000.include? ext }
      @pref = Array.new( ext_jpeg ) if @pref.include? 'JP2'
    end

    for fname in files do
      if /\A([^.]*)\.(TIFF?|PNG)\Z/i.match( fname )
        page = PageData.new( fname,$1,args,@exts,@pref )
        scnt = page.fillStencilArray()
        if scnt > 0
          page.addSupplementaryFiles()
          push( page )
        end
      end
    end
  end

  # A wrapper for the jbig2 encoder. The jbig2 utility is called as many
  # times as needed to encode all pages with the given pages-per-dict value.
  def jbig2Encode()
    per_dict = @pageargs[:pages_per_dict]
    force = @pageargs[:force_update]

    has_jbig2 = false
    if /(win|w)32$/i.match( RUBY_PLATFORM )
      schar = ';'
      ext = '.exe'
      sep = '\\'
    else
      schar = ':'
      ext = ''
      sep = '/'
    end
    ENV['PATH'].split( schar ).each do |dir|
      if File.exists?( dir << sep << 'jbig2' << ext )
        has_jbig2 = true
        break
      end
    end

    unless has_jbig2
      $stderr.puts("JBIG2 compression has been requested, but the encoder is not available.")
      $stderr.puts( "  I'll use CCITT Group 4 fax compression instead." )
      return false
    end

    pidx = 0
    needs_update = force
    toConvert = Array.new()
    each_index do |i|
      p = fetch(i)
      pidx += 1
      p.stencils.each do |s|
        toConvert << s[:path]
        s[:jbig2path] = s[:path].sub( /\.(TIFF?|PNG)\Z/i,'.jbig2' )
        s[:jbig2dict] = toConvert[0].sub( /\.(TIFF?|PNG)\Z/i,'.sym' )
        if needs_update == false
          needs_update = true unless File.exists? s[:jbig2path] and File.exists? s[:jbig2dict]
        end
      end

      if pidx == per_dict or i == length - 1
        # The jbig2 encoder processes a bunch of files at once, producing 
        # pages which depend from a shared dictionary. Thus we can skip this
        # stage only if both the dictionary and each of the individual pages
        # are already found on the disk
        if needs_update
          IO.popen("jbig2 -s -p " << toConvert.join(' ') ) do |f|
            out = f.gets
            $stderr.puts out unless out.nil?
          end
          return false if $?.exitstatus > 0

          toConvert.each_index do |j|
            oname = sprintf( "output.%04d",j )
            File.rename( oname,toConvert[j].sub( /\.(TIFF?|PNG)\Z/i,'.jbig2' ) ) if File.exists? oname
          end
          File.rename( 'output.sym',toConvert[0].sub( /\.(TIFF?|PNG)\Z/i,'.sym' ) ) if File.exists? 'output.sym'
        end

        toConvert.clear
        needs_update = force
        pidx = 0
      end
    end
    return true
  end
end
