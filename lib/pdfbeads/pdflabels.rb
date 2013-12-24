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

# Parse a specification string passed to pdfbeads via its -L (--labels)
# option and convert it into a sequence of ranges which can be used for
# building a PageLabels dictionary embeddable into the PDF file.
# The specification format is based on the PDF format description,
# section 12.4.2. and looks as follows:
#
# * ranges are separated with a semicolon;
#
# * each range consists from a physical number of the first page,
#   folowed by a colon and a number format description;
#
# * the number format consists from an optional prefix, followed
#   by a percent sign, an optional number indicating the value of the
#   numeric portion for the first page label in the range, and a single
#   Latin letter indicating the desired numbering style;
#
# * the following numbering styles are supported:
#   [D] --  Decimal arabic numerals;
#   [R] --  Uppercase roman numerals;
#   [r] --  Lowercase roman numerals;
#   [A] --  Uppercase Romam letters (A to Z for the first 26 pages,
#           AA to ZZ for the next 26, and so on);
#   [a] --  Lowercase letters (a to z for the first 26 pages,
#           aa to zz for the next 26, and so on).
#
# For example if a book starts from two unnumbered title pages, followed
# by 16 pages numbered with Roman digits, and then goes the Arabic numeration,
# which however starts from 17, then the following label specification 
# string would be appropriate:
# +"0:Title %D;2:%R;18:%16D"+

class PDFBeads::PDFBuilder::PDFLabels < Array
  def initialize( arg )
    descrs = arg.split(/;/)
    descrs.each do |descr|
      rng = Hash.new()
      fields = descr.split(/:/, 2)
      if /\d+/.match( fields[0] )
        rng[:first] = fields[0].to_i
        if fields.length > 1 and /([^%]*)%?(\d*)([DRrAa]?)/.match(fields[1])
          rng[:prefix]  = $1 unless $1 == ''
          rng[:start ]  = $2.to_i unless $2 == ''
          rng[:style ]  = $3 unless $3 == ''
        end
        push(rng)
      end
    end
  end

  # Convert a physical page number into the label we would like to be displayed
  # for this page in the PDF viewer.
  def getPageLabel( rng_id,page_id )
    rng = self[rng_id]
    prefix = ''
    start_num = 1

    start_num = rng[:start] if rng.has_key? :start
    pnum = page_id - rng[:first] + start_num

    prefix = rng[:prefix] if rng.has_key? :prefix

    snum = ''
    snum = pnum2string( pnum,rng[:style] ) if rng.has_key? :style

    return "#{prefix}#{snum}"
  end

  private

  def int2roman( num )
    numerals = Hash[  
      1   => "I",  4  => "IV",   5 => "V", 9   => "IX",
      10  => "X", 40  => "XL",  50 => "L", 90  => "XC",
      100 => "C", 400 => "CD", 500 => "D", 900 => "CM", 1000 => "M"
    ]
    res = ''

    numerals.keys.sort{ |a,b| b <=> a }.each do |val|
      while num >= val
        res << numerals[val]
        num -= val
      end
    end

    return res
  end

  def int2ralph( num )
    quot, mod = num.divmod(26)
    return (mod + 96).chr * (quot + 1)
  end

  def pnum2string( pnum,style )
    case style
    when 'R'
      return int2roman(pnum)
    when 'r'
      return int2roman(pnum).downcase
    when 'A'
      return int2ralph(pnum)
    when 'a'
      return int2ralph(pnum).downcase
    else
      return pnum.to_s
    end
  end
end
