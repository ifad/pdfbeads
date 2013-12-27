#
$:.push File.expand_path('../lib', __FILE__)
require 'pdfbeads/version'

Gem::Specification.new do |s|

  s.name = 'pdfbeads'
  s.version = PDFBeads::VERSION
  s.author = ['Alexey Kryukov']
  s.email  = ['amkryukov@gmail.com']
  s.homepage = 'https://github.com/ifad/pdfbeads'
  s.summary = 'Convert scanned images to a single PDF file.'
  s.description = <<-EOD
    PDFBeads is a small utility written in Ruby which takes scanned page
    images and converts them into a single PDF file. Unlike other PDF creation
    tools, PDFBeads attempts to implement the approach typically used for DjVu
    books. Its key feature is separating scanned text (typically black, but
    indexed images with a small number of colors are also accepted) from
    halftone pictures. Each type of graphical data is encoded into its own
    layer with a specific compression method and resolution.
  EOD


  s.files             = `git ls-files`.split("\n")
  s.require_paths     = ["lib"]

  s.executables << 'pdfbeads'

  s.add_runtime_dependency('nokogiri')
  s.add_runtime_dependency('iconv')
  s.add_runtime_dependency('rmagick')

  s.extra_rdoc_files = %w( README COPYING ChangeLog )

end
