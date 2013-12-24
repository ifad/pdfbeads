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

# Read table of contents from an UTF-8 text file and prepare it for
# placing into a PDF document. The syntax of the TOC file is simple.
# Each line describes a single outline item according to the following
# pattern:
#
# <indent>"Title" "Page Number" [0|-|1|+]
#
# The indent is used to determine the level of this outline item: it may
# consist either of spaces or of tabs, but it is not allowed to 
# mix both characters in the same file. The title and page number are
# separated with an arbitrary number of whitespace characters and are
# normally enclosed into double quotes. The third, optional argument
# specifies if this TOC item should be displayed unfolded by default
# (i. e. if its descendants should be visible).
#
# The reference to a TOC file can be passed to pdfbeads via the *-C*
# (or *--toc*) option. It is recommended to use this option in combination
# with the *-L* (or *--labels*) parameter, which allows to specify an
# alternate page numbering for a PDF file: thus your TOC file may
# contain the same page numbers, as the original book, so that there is
# no need to care about any numbering offsets.

class PDFBeads::PDFBuilder::PDFTOC < Array
  # This class represents a single TOC item with its parent node and
  # next/previous siblings.
  class PDFTOCItem < Hash
    def getChildrenCount()
      cnt = self[:children].length
      self[:children].each do |child|
        if child[:open] and child[:children].length > 0
          cnt = cnt + child.getChildrenCount
        end
      end
      return cnt
    end

    def prevSibling( indent )
      if has_key? :parent and self[:indent] > indent
        return self[:parent].prevSibling( indent )
      end

      return self if self[:indent] == indent
      return nil
    end
  end

  def initialize( fpath )
    root = PDFTOCItem[
      :indent   => -1,
      :open     => true,
      :children => Array.new()
    ]
    push( root )
    parseTOC( fpath,root )
  end

  private

  def parseTOC( path,root )
    File.open( path,'r' ) do |fin|
      fin.set_encoding 'UTF-8' if fin.respond_to? :set_encoding
      prev = root
      indent_char = "\x00"
      fin.each do |fl|
        next if /^\#/.match( fl )

        parts = fl.scan(/".*?"|\S+/)
        if parts.length > 1
          title = parts[0].gsub(/\A"/m,"").gsub(/"\Z/m, "")
          ref   = parts[1].gsub(/\A"/m,"").gsub(/"\Z/m, "")
          begin
            title = Iconv.iconv( "utf-16be", "utf-8", title ).first
          rescue
            $stderr.puts("Error: TOC should be specified in utf-8")
            return
          end

          entry = PDFTOCItem[
            :title    => title,
            :ref      => ref,
            :indent   => 0,
            :children => Array.new()
          ]
          if /^([ \t]+)/.match(fl)
            indent = $1
            indent.each_byte do |char|
              if indent_char == "\x00"
                indent_char = char
              elsif not char.eql? indent_char
                $stderr.puts("Error: you should not mix spaces and tabs in TOC indents\n")
                return
              end
            end

            entry[:indent] = indent.length
          end

          if entry[:indent] < prev[:indent]
            prev = prev.prevSibling( entry[:indent] )
          end
          if prev.nil?
            $stderr.puts("Error: a TOC item seems to have a wrong indent\n")
            return
          end

          if entry[:indent] == prev[:indent]
            entry[:parent] = prev[:parent]
            entry[:parent][:children].push( entry )
            entry[:prev] = prev
            prev[:next] = entry
          elsif entry[:indent] > prev[:indent]
            entry[:parent] = prev
            prev[:children].push(entry)
          end

          if parts.length > 2 and (parts[2] == '+' or parts[2] == '1')
            entry[:open] = true
          else
            entry[:open] = false
          end

          push( entry )
          prev = entry
        end
      end
    end
  end
end
