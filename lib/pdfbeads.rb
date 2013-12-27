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

require 'iconv'
require 'zlib'
require 'nokogiri'

require 'RMagick'
include Magick

unless ''.respond_to? :ord
  $KCODE = 'u'
  require 'jcode'
end

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

  # In ruby 1.9 sometimes we have to mark a string as UTF-8 encoded
  # even if we certainly know it is not.
  unless self.method_defined? :to_text
    def to_text()
      force_encoding 'UTF-8' if respond_to? :force_encoding
      return self
    end
  end

  # Get a Unicode ordinal for an encoded character (there is no standard method
  # in Ruby < 1.9 to do that)
  unless self.method_defined? :ord
    def ord()
      begin
        return Iconv.iconv( 'utf-16be','utf-8',self ).first.unpack('n')[0]
      rescue
        return 0x3F # Question mark
      end
    end
  end
end

require 'imageinspector'

module PDFBeads
  require 'pdfbeads/version'
  require 'pdfbeads/pdfbuilder'
  require 'pdfbeads/pdfpage'
end
