#!/usr/bin/env ruby
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

class PDFBeads::PDFBuilder::Dict < Hash
  def initialize(pairs = {})
    update( pairs )
    super
  end

  def to_s()
    s = "<<\n"
    each_pair{ |key, value| s << "/#{key} #{value}\n" }
    s << ">>\n"
    s
  end
end

class PDFBeads::PDFBuilder::XObj
  @@next_id = 1

  def initialize(d = {}, stream = nil)
    reinit(d, stream)
    @id = @@next_id
    @@next_id += 1
  end

  def to_s()
    s = ''
    s << @d.to_s
    unless @stream.nil?
      s << "stream\n"
      s << @stream
      s << "\nendstream\n"
    end
    s << "endobj\n"
    return s
  end

  def reinit(d = {}, stream = nil)
    @d = PDFBuilder::Dict.new(d)
    @stream = stream
    @stream.to_binary if stream.kind_of? String
    @d['Length'] = stream.length.to_s unless stream.nil?
  end

  def addToDict(key, value)
    @d[key] = value
  end

  def hasInDict(key)
    @d.has_key? key
  end

  def getFromDict(key)
    @d[key]
  end

  def removeFromDict(key)
    @d.delete(key)
  end

  def getID
    @id
  end

  def dictLength
    @d.length
  end
end

class PDFBeads::PDFBuilder::Doc
  def initialize()
    @objs  = Array.new()
    @pages = Array.new()
  end

  def addObject(o)
    @objs.push(o)
    o
  end

  def addPage(p)
    @pages.push(p)
    addObject(p)
  end

  def to_s()
    a = ''
    j = 0
    offsets = Array.new()

    add = lambda{ |x|
      x.to_binary
      a << x
      j += x.length
    }
    add.call( "%PDF-1.5\n" )
    @objs.each do |xobj|
      offsets << j
      add.call( "#{xobj.getID} 0 obj\n" )
      add.call( "#{xobj.to_s}\n" )
    end
    xrefstart = j
    a << "xref\n"
    a << "0 #{offsets.length + 1}\n"
    a << "0000000000 65535 f \n"
    offsets.each do |off|
      a << sprintf("%010d 00000 n \n", off)
    end
    a << "\n"
    a << "trailer\n"
    a << "<< /Size #{offsets.length + 1} /Root 1 0 R /Info 2 0 R >>\n"
    a << "startxref\n"
    a << "#{xrefstart.to_s}\n"
    a << "%%EOF"

    a
  end
end
