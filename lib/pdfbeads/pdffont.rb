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

# This class provides auxiliary data (such as basic font properties or
# a width and a PostScript name for an arbitrary Unicode codepoint)
# for building a PDF font object with an arbitrary set of supported
# characters. Note that the returned properties (both of the entire font
# and individual characters) are hardcoded and correspond to those of
# Times New Roman. The reason is that we need this font just for a hidden
# text layer, so visual appearance doesn't matter.
# 
class PDFBeads::PDFBuilder::FontDataProvider
  # Access a hardcoded set of standard font properties (Ascent, Descent, etc.)
  attr_reader :header

  def initialize()
    @header = Hash[
      'Ascent'      => 694,
      'XHeight'     => 447,
      'CapHeight'   => 662,
      'Descent'     => -213,
      'Flags'       => 34,
      'FontBBox'    => '[ -79 -216 1009 913 ]',
      'ItalicAngle' => 0,
      'StemV'       => 81
    ]

    @chardata = Hash[
      -1     => ["/.notdef", 250],
      0x0020 => ["/space", 250],
      0x0021 => ["/exclam", 333],
      0x0022 => ["/quotedbl", 408],
      0x0023 => ["/numbersign", 500],
      0x0024 => ["/dollar", 500],
      0x0025 => ["/percent", 833],
      0x0026 => ["/ampersand", 778],
      0x0027 => ["/quotesingle", 180],
      0x0028 => ["/parenleft", 333],
      0x0029 => ["/parenright", 333],
      0x002A => ["/asterisk", 500],
      0x002B => ["/plus", 564],
      0x002C => ["/comma", 250],
      0x002D => ["/hyphen", 333],
      0x002E => ["/period", 250],
      0x002F => ["/slash", 278],
      0x0030 => ["/zero", 500],
      0x0031 => ["/one", 500],
      0x0032 => ["/two", 500],
      0x0033 => ["/three", 500],
      0x0034 => ["/four", 500],
      0x0035 => ["/five", 500],
      0x0036 => ["/six", 500],
      0x0037 => ["/seven", 500],
      0x0038 => ["/eight", 500],
      0x0039 => ["/nine", 500],
      0x003A => ["/colon", 278],
      0x003B => ["/semicolon", 278],
      0x003C => ["/less", 564],
      0x003D => ["/equal", 564],
      0x003E => ["/greater", 564],
      0x003F => ["/question", 444],
      0x0040 => ["/at", 921],
      0x0041 => ["/A", 722],
      0x0042 => ["/B", 667],
      0x0043 => ["/C", 667],
      0x0044 => ["/D", 722],
      0x0045 => ["/E", 611],
      0x0046 => ["/F", 556],
      0x0047 => ["/G", 722],
      0x0048 => ["/H", 722],
      0x0049 => ["/I", 333],
      0x004A => ["/J", 389],
      0x004B => ["/K", 722],
      0x004C => ["/L", 611],
      0x004D => ["/M", 889],
      0x004E => ["/N", 722],
      0x004F => ["/O", 722],
      0x0050 => ["/P", 556],
      0x0051 => ["/Q", 722],
      0x0052 => ["/R", 667],
      0x0053 => ["/S", 556],
      0x0054 => ["/T", 611],
      0x0055 => ["/U", 722],
      0x0056 => ["/V", 722],
      0x0057 => ["/W", 944],
      0x0058 => ["/X", 722],
      0x0059 => ["/Y", 722],
      0x005A => ["/Z", 611],
      0x005B => ["/bracketleft", 333],
      0x005C => ["/backslash", 278],
      0x005D => ["/bracketright", 333],
      0x005E => ["/asciicircum", 469],
      0x005F => ["/underscore", 500],
      0x0060 => ["/grave", 333],
      0x0061 => ["/a", 444],
      0x0062 => ["/b", 500],
      0x0063 => ["/c", 444],
      0x0064 => ["/d", 500],
      0x0065 => ["/e", 444],
      0x0066 => ["/f", 333],
      0x0067 => ["/g", 500],
      0x0068 => ["/h", 500],
      0x0069 => ["/i", 278],
      0x006A => ["/j", 278],
      0x006B => ["/k", 500],
      0x006C => ["/l", 278],
      0x006D => ["/m", 778],
      0x006E => ["/n", 500],
      0x006F => ["/o", 500],
      0x0070 => ["/p", 500],
      0x0071 => ["/q", 500],
      0x0072 => ["/r", 333],
      0x0073 => ["/s", 389],
      0x0074 => ["/t", 278],
      0x0075 => ["/u", 500],
      0x0076 => ["/v", 500],
      0x0077 => ["/w", 722],
      0x0078 => ["/x", 500],
      0x0079 => ["/y", 500],
      0x007A => ["/z", 444],
      0x007B => ["/braceleft", 480],
      0x007C => ["/bar", 200],
      0x007D => ["/braceright", 480],
      0x007E => ["/asciitilde", 541],
      0x00A1 => ["/exclamdown", 333],
      0x00A2 => ["/cent", 500],
      0x00A3 => ["/sterling", 500],
      0x00A4 => ["/currency", 500],
      0x00A5 => ["/yen", 500],
      0x00A6 => ["/brokenbar", 200],
      0x00A7 => ["/section", 500],
      0x00A8 => ["/dieresis", 333],
      0x00A9 => ["/copyright", 760],
      0x00AA => ["/ordfeminine", 276],
      0x00AB => ["/guillemotleft", 500],
      0x00AC => ["/logicalnot", 564],
      0x00AD => ["/softhyphen", 333],
      0x00AE => ["/registered", 760],
      0x00AF => ["/macron", 333],
      0x00B0 => ["/degree", 400],
      0x00B1 => ["/plusminus", 564],
      0x00B2 => ["/twosuperior", 300],
      0x00B3 => ["/threesuperior", 300],
      0x00B4 => ["/acute", 333],
      0x00B5 => ["/mu", 500],
      0x00B6 => ["/paragraph", 453],
      0x00B7 => ["/periodcentered", 250],
      0x00B8 => ["/cedilla", 333],
      0x00B9 => ["/onesuperior", 300],
      0x00BA => ["/ordmasculine", 310],
      0x00BB => ["/guillemotright", 500],
      0x00BC => ["/onequarter", 750],
      0x00BD => ["/onehalf", 750],
      0x00BE => ["/threequarters", 750],
      0x00BF => ["/questiondown", 444],
      0x00C0 => ["/Agrave", 722],
      0x00C1 => ["/Aacute", 722],
      0x00C2 => ["/Acircumflex", 722],
      0x00C3 => ["/Atilde", 722],
      0x00C4 => ["/Adieresis", 722],
      0x00C5 => ["/Aring", 722],
      0x00C6 => ["/AE", 889],
      0x00C7 => ["/Ccedilla", 667],
      0x00C8 => ["/Egrave", 611],
      0x00C9 => ["/Eacute", 611],
      0x00CA => ["/Ecircumflex", 611],
      0x00CB => ["/Edieresis", 611],
      0x00CC => ["/Igrave", 333],
      0x00CD => ["/Iacute", 333],
      0x00CE => ["/Icircumflex", 333],
      0x00CF => ["/Idieresis", 333],
      0x00D0 => ["/Eth", 722],
      0x00D1 => ["/Ntilde", 722],
      0x00D2 => ["/Ograve", 722],
      0x00D3 => ["/Oacute", 722],
      0x00D4 => ["/Ocircumflex", 722],
      0x00D5 => ["/Otilde", 722],
      0x00D6 => ["/Odieresis", 722],
      0x00D7 => ["/multiply", 564],
      0x00D8 => ["/Oslash", 722],
      0x00D9 => ["/Ugrave", 722],
      0x00DA => ["/Uacute", 722],
      0x00DB => ["/Ucircumflex", 722],
      0x00DC => ["/Udieresis", 722],
      0x00DD => ["/Yacute", 722],
      0x00DE => ["/Thorn", 556],
      0x00DF => ["/germandbls", 500],
      0x00E0 => ["/agrave", 444],
      0x00E1 => ["/aacute", 444],
      0x00E2 => ["/acircumflex", 444],
      0x00E3 => ["/atilde", 444],
      0x00E4 => ["/adieresis", 444],
      0x00E5 => ["/aring", 444],
      0x00E6 => ["/ae", 667],
      0x00E7 => ["/ccedilla", 444],
      0x00E8 => ["/egrave", 444],
      0x00E9 => ["/eacute", 444],
      0x00EA => ["/ecircumflex", 444],
      0x00EB => ["/edieresis", 444],
      0x00EC => ["/igrave", 278],
      0x00ED => ["/iacute", 278],
      0x00EE => ["/icircumflex", 278],
      0x00EF => ["/idieresis", 278],
      0x00F0 => ["/eth", 500],
      0x00F1 => ["/ntilde", 500],
      0x00F2 => ["/ograve", 500],
      0x00F3 => ["/oacute", 500],
      0x00F4 => ["/ocircumflex", 500],
      0x00F5 => ["/otilde", 500],
      0x00F6 => ["/odieresis", 500],
      0x00F7 => ["/divide", 564],
      0x00F8 => ["/oslash", 500],
      0x00F9 => ["/ugrave", 500],
      0x00FA => ["/uacute", 500],
      0x00FB => ["/ucircumflex", 500],
      0x00FC => ["/udieresis", 500],
      0x00FD => ["/yacute", 500],
      0x00FE => ["/thorn", 500],
      0x00FF => ["/ydieresis", 500],
      0x0131 => ["/dotlessi", 278],
      0x0141 => ["/Lslash", 611],
      0x0142 => ["/lslash", 278],
      0x0152 => ["/OE", 889],
      0x0153 => ["/oe", 722],
      0x0160 => ["/Scaron", 556],
      0x0161 => ["/scaron", 389],
      0x0178 => ["/Ydieresis", 722],
      0x017D => ["/Zcaron", 611],
      0x017E => ["/zcaron", 444],
      0x0192 => ["/florin", 488],
      0x02C6 => ["/circumflex", 333],
      0x02C7 => ["/caron", 333],
      0x02D8 => ["/breve", 333],
      0x02D9 => ["/dotaccent", 333],
      0x02DA => ["/ring", 333],
      0x02DB => ["/ogonek", 333],
      0x02DC => ["/tilde", 333],
      0x02DD => ["/hungarumlaut", 333],
      0x0338 => ["/Alphatonos", 722],
      0x0388 => ["/Epsilontonos", 694],
      0x0389 => ["/Etatonos", 808],
      0x038A => ["/Iotatonos", 412],
      0x038C => ["/Omicrontonos", 722],
      0x038E => ["/Upsilontonos", 816],
      0x038F => ["/Omegatonos", 744],
      0x03AC => ["/alphatonos", 522],
      0x03AD => ["/epsilontonos", 420],
      0x03AE => ["/etatonos", 522],
      0x03AF => ["/iotatonos", 268],
      0x0390 => ["/iotadieresistonos", 268],
      0x0391 => ["/Alpha", 722],
      0x0392 => ["/Beta", 667],
      0x0393 => ["/Gamma", 578],
      0x0394 => ["/Delta", 643],
      0x0395 => ["/Epsilon", 611],
      0x0396 => ["/Zeta", 611],
      0x0397 => ["/Eta", 722],
      0x0398 => ["/Theta", 722],
      0x0399 => ["/Iota", 333],
      0x039A => ["/Kappa", 722],
      0x039B => ["/Lambda", 724],
      0x039C => ["/Mu", 889],
      0x039D => ["/Nu", 722],
      0x039E => ["/Xi", 643],
      0x039F => ["/Omicron", 722],
      0x03A0 => ["/Pi", 722],
      0x03A1 => ["/Rho", 556],
      0x03A3 => ["/Sigma", 582],
      0x03A4 => ["/Tau", 611],
      0x03A5 => ["/Upsilon", 722],
      0x03A6 => ["/Phi", 730],
      0x03A7 => ["/Chi", 722],
      0x03A8 => ["/Psi", 737],
      0x03A9 => ["/Omega", 744],
      0x03AA => ["/Iotadieresis", 333],
      0x03AB => ["/Upsilondieresis", 722],
      0x03B0 => ["/upsilondieresistonos", 496],
      0x03B1 => ["/alpha", 522],
      0x03B2 => ["/beta", 508],
      0x03B3 => ["/gamma", 440],
      0x03B4 => ["/delta", 471],
      0x03B5 => ["/epsilon", 420],
      0x03B6 => ["/zeta", 414],
      0x03B7 => ["/eta", 522],
      0x03B8 => ["/theta", 480],
      0x03B9 => ["/iota", 268],
      0x03BA => ["/kappa", 502],
      0x03BB => ["/lambda", 484],
      0x03BC => ["/mu", 500],
      0x03BD => ["/nu", 452],
      0x03BE => ["/xi", 444],
      0x03BF => ["/omicron", 500],
      0x03C0 => ["/pi", 504],
      0x03C1 => ["/rho", 500],
      0x03C2 => ["/sigma1", 396],
      0x03C3 => ["/sigma", 540],
      0x03C4 => ["/tau", 400],
      0x03C5 => ["/upsilon", 496],
      0x03C6 => ["/phi", 578],
      0x03C7 => ["/chi", 444],
      0x03C8 => ["/psi", 624],
      0x03C9 => ["/omega", 658],
      0x03CA => ["/iotadieresis", 268],
      0x03CB => ["/upsilondieresis", 496],
      0x03CC => ["/omicrontonos", 500],
      0x03CD => ["/upsilontonos", 496],
      0x03CE => ["/omegatonos", 658],
      0x0401 => ["/afii10023", 611],
      0x0402 => ["/afii10051", 752],
      0x0403 => ["/afii10052", 578],
      0x0404 => ["/afii10053", 660],
      0x0405 => ["/afii10054", 556],
      0x0406 => ["/afii10055", 333],
      0x0407 => ["/afii10056", 333],
      0x0408 => ["/afii10057", 389],
      0x0409 => ["/afii10058", 872],
      0x040A => ["/afii10059", 872],
      0x040B => ["/afii10060", 741],
      0x040C => ["/afii10061", 667],
      0x040E => ["/afii10062", 708],
      0x040F => ["/afii10145", 722],
      0x0410 => ["/afii10017", 722],
      0x0411 => ["/afii10018", 574],
      0x0412 => ["/afii10019", 667],
      0x0413 => ["/afii10020", 578],
      0x0414 => ["/afii10021", 682],
      0x0415 => ["/afii10022", 611],
      0x0416 => ["/afii10024", 896],
      0x0417 => ["/afii10025", 501],
      0x0418 => ["/afii10026", 722],
      0x0419 => ["/afii10027", 722],
      0x041A => ["/afii10028", 667],
      0x041B => ["/afii10029", 678],
      0x041C => ["/afii10030", 889],
      0x041D => ["/afii10031", 722],
      0x041E => ["/afii10032", 722],
      0x041F => ["/afii10033", 722],
      0x0420 => ["/afii10034", 556],
      0x0421 => ["/afii10035", 667],
      0x0422 => ["/afii10036", 611],
      0x0423 => ["/afii10037", 708],
      0x0424 => ["/afii10038", 790],
      0x0425 => ["/afii10039", 722],
      0x0426 => ["/afii10040", 722],
      0x0427 => ["/afii10041", 650],
      0x0428 => ["/afii10042", 1009],
      0x0429 => ["/afii10043", 1009],
      0x042A => ["/afii10044", 706],
      0x042B => ["/afii10045", 872],
      0x042C => ["/afii10046", 574],
      0x042D => ["/afii10047", 660],
      0x042E => ["/afii10048", 1028],
      0x042F => ["/afii10049", 667],
      0x0430 => ["/afii10065", 444],
      0x0431 => ["/afii10066", 509],
      0x0432 => ["/afii10067", 472],
      0x0433 => ["/afii10068", 410],
      0x0434 => ["/afii10069", 509],
      0x0435 => ["/afii10070", 444],
      0x0436 => ["/afii10072", 691],
      0x0437 => ["/afii10073", 395],
      0x0438 => ["/afii10074", 535],
      0x0439 => ["/afii10075", 535],
      0x043A => ["/afii10076", 486],
      0x043B => ["/afii10077", 499],
      0x043C => ["/afii10078", 633],
      0x043D => ["/afii10079", 535],
      0x043E => ["/afii10080", 500],
      0x043F => ["/afii10081", 535],
      0x0440 => ["/afii10082", 500],
      0x0441 => ["/afii10083", 444],
      0x0442 => ["/afii10084", 437],
      0x0443 => ["/afii10085", 500],
      0x0444 => ["/afii10086", 648],
      0x0445 => ["/afii10087", 500],
      0x0446 => ["/afii10088", 535],
      0x0447 => ["/afii10089", 503],
      0x0448 => ["/afii10090", 770],
      0x0449 => ["/afii10091", 770],
      0x044A => ["/afii10092", 517],
      0x044B => ["/afii10093", 672],
      0x044C => ["/afii10094", 456],
      0x044D => ["/afii10095", 429],
      0x044E => ["/afii10096", 747],
      0x044F => ["/afii10097", 460],
      0x0451 => ["/afii10071", 444],
      0x0452 => ["/afii10099", 483],
      0x0453 => ["/afii10100", 410],
      0x0454 => ["/afii10101", 429],
      0x0455 => ["/afii10102", 389],
      0x0456 => ["/afii10103", 278],
      0x0457 => ["/afii10104", 278],
      0x0458 => ["/afii10105", 278],
      0x0459 => ["/afii10106", 727],
      0x045A => ["/afii10107", 723],
      0x045B => ["/afii10108", 500],
      0x045C => ["/afii10109", 486],
      0x045E => ["/afii10110", 500],
      0x045F => ["/afii10193", 535],
      0x0462 => ["/afii10146", 648],
      0x0463 => ["/afii10194", 514],
      0x0472 => ["/afii10147", 722],
      0x0473 => ["/afii10195", 500],
      0x0474 => ["/afii10148", 771],
      0x0475 => ["/afii10196", 536],
      0x0490 => ["/afii10050", 450],
      0x0491 => ["/afii10098", 351],
      0x2013 => ["/endash", 500],
      0x2014 => ["/emdash", 1000],
      0x2018 => ["/quoteleft", 333],
      0x2019 => ["/quoteright", 333],
      0x201A => ["/quotesinglbase", 333],
      0x201C => ["/quotedblleft", 444],
      0x201D => ["/quotedblright", 444],
      0x201E => ["/quotedblbase", 444],
      0x2020 => ["/dagger", 500],
      0x2021 => ["/daggerdbl", 500],
      0x2022 => ["/bullet", 350],
      0x2026 => ["/ellipsis", 1000],
      0x2030 => ["/perthousand", 1000],
      0x2039 => ["/guilsinglleft", 333],
      0x203A => ["/guilsinglright", 333],
      0x20AC => ["/Euro", 500],
      0x2116 => ["/afii61352", 954],
      0x2122 => ["/trademark", 980],
      0x2202 => ["/partialdiff", 490],
      0x2212 => ["/minus", 564],
      0x221A => ["/radical", 552],
      0x221E => ["/infinity", 708],
      0x2248 => ["/approxequal", 564],
      0x2260 => ["/notequal", 564],
      0x2264 => ["/lessequal", 564],
      0x2265 => ["/greaterequal", 564],
      0xFB01 => ["/fi", 556],
      0xFB02 => ["/fl", 556],
    ]

    @encodings = Array.new()
    @wlists = Array.new()
  end

  # Return the width of a given UTF-8 string formatted with our hardcoded
  # font at a given point size
  def getLineWidth( line,size )
    w = 0.0
    line.each_char do |uc|
      begin
        w += chardata( uc.ord )[1] * size / 1000.0
      rescue
        rawbytes = uc.unpack( 'C*' )
        bs = ''
        rawbytes.each{ |b| bs << sprintf( "%02x",b ) }
        $stderr.puts( "Warning: an invalid UTF-8 sequence (#{bs}) in the hOCR data." )
        w += ( @chardata[0x003F][1] * size / 1000.0 ) * rawbytes.length
      end
    end
    w.to_f
  end

  # Take an array of UTF-8 characters and return an array of the
  # corresponding PostScript glyph names
  def getEncoding( enc )
    ret = Array.new()
    enc.each do |char|
      ret << chardata( char.ord )[0]
    end
    ret
  end

  # Take an array of UTF-8 characters and return an array of the
  # corresponding glyph widths
  def getWidths( enc )
    ret = Array.new()
    enc.each do |char|
      ret << chardata( char.ord )[1]
    end
    ret
  end

  # Take an array of UTF-8 characters and return the corresponding
  # ToUnicode cmap object
  def getCMAP( enc )
    cmap = [
      "/CIDInit /ProcSet findresource begin\n",
      "12 dict begin\n",
      "begincmap\n",
      "/CIDSystemInfo\n",
      "<<\n",
      "  /Registry ( PDFBeads )\n",
      "  /Ordering ( Custom )\n",
      "  /Supplement 0\n",
      ">> def\n",
      "/CMapName /PDFBeads-Custom def\n",
      "/CMapType 2 def\n",
      "1 begincodespacerange\n",
      "<00> <FF>\n",
      "endcodespacerange\n",
    ].join( '' )
    ranges = Array.new()
    cur_range = nil
    prev = -1
    numbfchar = 0
    enc.each_index do |i|
      cur = enc[i].ord
      if cur == prev + 1
        if cur_range.nil?
          cur_range = Hash[
            'start' => i-1,
            'end'   => i,
            'uni'   => prev
          ]
          numbfchar -= 1
        else
          cur_range['end'] = i
        end
      elsif cur_range != nil
        ranges << cur_range
        cur_range = nil
      end

      if cur_range.nil? and cur != -1
        numbfchar += 1
      end
      prev = cur
    end

    unless cur_range.nil?
      ranges << cur_range
      cur_range = nil
    end

    if ranges.length > 0
      cmap << "#{ranges.length} beginbfrange\n"
      ranges.each do |cr|
        cmap << sprintf( "<%02X> <%02X> <%04X>\n",
          cr['start'], cr['end'], cr['uni'] )
      end
      cmap << "endbfrange\n"
    end

    if numbfchar > 0
      cmap += "%d beginbfchar\n" % numbfchar
      enc.each_index do |i|
        in_range = false
        ranges.each do |cr|
          if i >= cr['start'] and i <= cr['end']
            in_range = true
            break
          end
        end

        cmap << sprintf( "<%02X> <%04X>\n", i, enc[i].ord ) unless in_range
      end

      cmap << "endbfchar\n"
    end

    cmap << "endcmap\n"
    cmap << "CMapName currentdict /CMap defineresource pop\n"
    cmap << "end\n"
    cmap << "end\n"

    toUnicode = PDFBuilder::XObj.new( Hash[
      'Filter' => '/FlateDecode',
    ], Zlib::Deflate.deflate( cmap,9 ) )
    toUnicode
  end

  def chardata( uni )
    @chardata.fetch( uni ) do |u|
      [ sprintf( "/uni%04X",uni ), 500 ]
    end
  end
end
