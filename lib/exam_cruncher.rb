#! /usr/bin/env ruby
# -*- encoding: utf-8 -*-

# Author:: Olivier Lange (mailto:olange@petit-atelier.ch)
# Copyright:: (c) 2011 Tristan Zand & Olivier Lange
# License:: GNU GPL, either v3 or (at your option) any later version.

require 'optparse'
require 'pathname'
require 'colored'
require_relative 'exam'

# Classe utilitaire qui commande l'extraction des métadonnées d'une
# série d'images DICOM et leur transcription dans un fichier CSV,
# d'après les arguments de la ligne de commande.
#
# Usage:
#   ExamCruncher.crunch ARGV
#   ExamCruncher.crunch ARGV, { :force => true }

class ExamCruncher

  attr_reader :options
  attr_reader :images_base_dir
  attr_reader :output_file

  DEFAULT_OPTIONS = {
    :csv_export => true, :html_export => false, :element_set => :all,
    :force => false, :recurse => true, :dry_run => false, :verbose => false
  }

  LICENSE = """
  Copyright (c) 2011 Tristan Zand & Olivier Lange\n
  This program comes with ABSOLUTELY NO WARRANTY. It is free software
  and you are welcome to redistribute it under the terms of the GNU
  General Public License, either v3 or any later version. Please see
  the README file that comes along the source code of the program.
  """

  def self.crunch( args, options = {})
    ExamCruncher.new( options) do |cruncher|
      cruncher.crunch( args)
    end
  end

  def initialize( options = {})
    @options = DEFAULT_OPTIONS.merge( options)
    @images_base_dir = nil

    @executable_name = File.split( $0)[ 1]
    @options_parser = build_options_parser

    yield self if block_given?
  end

  def crunch( args)
    parse_arguments_from!( args)

    info( "snifff", "for directories within %s/" % @images_base_dir)
    image_dirs, count = collect_subdirs_of @images_base_dir

    error( "found no directories containing any files, exiting", 2) if count.zero?
    info( "mmmmhh", "found %d candidate director%s" \
      % [ count, count > 1 ? "ies" : "y"])

    image_dirs.each do |input_dir|
      info( "sluurp", "images from directory %s/ ..." % input_dir)
      exam = Exam.new( input_dir)
      if exam.empty?
        info( "ouuups", "found no DICOM images, skipping that directory")
        next
      end

      output_file = get_output_file_for( input_dir)
      check_if_output_exists( output_file)

      unless @options[ :dry_run]
        info( "crunch", "to CSV file %s ..." % output_file)
        open( output_file, "w") { |f| exam.to_csv f }

        # TODO: info( "cronch", "to HTML"); exam.to_html
      end
    end
    info( "buuurp\n")
  end

  private

  # Collecte et retourne la liste des sous-dossiers qui contienne un fichier
  # au moins, à partir d'un chemin d'accès, ainsi que le nombre de dossiers
  # collectés -- à moins que l'option :recurse ait été définie comme +false+,
  # dans quel cas le chemin d'accès de base est retourné tel quel.
  def collect_subdirs_of( base_dir)
    return [ base_dir ], 1 unless @options[ :recurse]
    subdirs = []
    Pathname.new( base_dir).find do |path|
      next unless path.directory?
      Find.prune if excluded_directory?( path)
      subdirs << path.to_s if candidate_directory?( path)
    end
    return subdirs, subdirs.count
  end

  def excluded_directory?( pathname)
    # raise TypeError unless pathname.kind_of? Pathname
    pathname.fnmatch? "**/.svn", File::FNM_PATHNAME
  end

  def candidate_directory?( pathname)
    # raise TypeError unless pathname.kind_of? Pathname
    it_contains_a_file = false
    Dir.glob( pathname.join( "*")) do |path|
      next if path.end_with?( ".csv")
      it_contains_a_file = File.file?( path)
      break if it_contains_a_file
    end
    it_contains_a_file
  end

  # Reporte une erreur si un fichier de sortie CSV existe déjà et que
  # l'option :force n'a pas été spécifiée.
  def check_if_output_exists( output_file)
    if File.exists? output_file
      if @options[ :force]
        warn( "Overwriting file %s".red % output_file)
      else
        error( "Error: file %s exists, use --force to overwrite".red \
          % output_file, 1)
      end
    end
  end

  # Normalise un chemin d'accès relatif ou absolu, en supprimant les
  # séparateurs et les segments '.' ou '..' superflus. Noter que le
  # dernier séparateur en particulier est supprimé. Par exemple,
  # "./test/valid-dicom/XY/../" deviendrait "test/valid-dicom".
  def normalize_path( path)
    Pathname.new( path).cleanpath.to_s
  end

  # Compose un nom de fichier CSV d'après le chemin d'accès à un dossier
  # d'images, en ajoutant '.csv' au dernier segment du chemin d'accès.
  # Par exemple, pour le dossier "test/valid-dicom/LAPIN2/", retournerait
  # le nom de fichier "test/valid-dicom/LAPIN2.csv".
  def get_output_file_for( dirname)
    dirpath = Pathname.new( dirname).cleanpath
    output_file = "#{dirpath.basename}.csv"   # dernier segment
    dirpath.parent.join( output_file).to_s
  end

  # Transcrit les valeurs des *options et arguments* de la ligne de
  # commande dans les variables d'instance. Altère le tableau 'args'.
  # Reporte une erreur si l'un des arguments ou options sont invalides.
  def parse_arguments_from!( args)
    parse_options_from! args

    if args.empty?
      error( "Error: you must supply a base directory name\n".red \
        + @options_parser.help, 2)
    end

    @images_base_dir = normalize_path args[ 0]
  end

  # Transcrit les valeurs des *options* de la ligne de commande dans la
  # variable d'instance 'options' (un hash). Altère le tableau 'args',
  # dont les options identifiées sont retirées. Soulève une exception
  # si l'une des options ou son argument sont invalides.
  def parse_options_from!( args)
    begin
      @options_parser.parse!( args)
    rescue \
      OptionParser::InvalidArgument,
      OptionParser::InvalidOption,
      OptionParser::MissingArgument => ex
      error( "%s\n%s" \
        % [ ex.message.capitalize.red, @options_parser.help ], 1)
    end
  end

  # Assemble l'analyseur des options de la ligne de commande
  # spécifiques à ce programme.
  def build_options_parser
    OptionParser.new do |opts|
      opts.banner = \
          "\nConverts the metadata in a serie of DICOM image files" \
        + "\nto CSV and an HTML graph of the X-ray tube current.\n" \
        + "\nUsage:" \
        + "\n  %s [options] dicom_base_dir\n" % @executable_name

      opts.separator "\nOptions:"

      opts.on( "--[no-]csv", "Exports the DICOM metadata as CSV " \
        + "(default %s)." % @options[ :csv_export]) do |csv|
        @options[ :csv_export] = csv
      end

      # [ TODO
      opts.on( "--[no-]html", "Graph the DICOM metadata as HTML " \
        + "(default %s)." % @options[ :html_export]) do |html|
        @options[ :html_export] = html
      end # ]

      opts.on( "-f", "--[no-]force", "Overwrite existing files " \
        + "(default %s)." % @options[ :force]) do |force|
        @options[ :force] = force
      end

      # [ TODO
      opts.on( "-r", "--[no-]recurse", "Recurse into directories " \
        + "(default %s)." % @options[ :recurse]) do |recurse|
        @options[ :recurse] = recurse
      end # ]

      # [ FIXME: demander à Tristan
      opts.on( "--elements SET", [ :all, :doseff],
        "Set of elements in the export (all, doseff; " \
        + "default %s)." % @options[ :element_set]) do |eltset|
        @options[ :element_set] = eltset
      end # ]

      opts.on( "-v", "--verbose", "Run more verbosely " \
        + "(default %s)." % @options[ :verbose]) do |verb|
        @options[ :verbose] = verb
      end

      opts.on( "--dry-run",
        "Parse options and files, but do not write anything.") do
        @options[ :dry_run] = true
      end

      opts.separator "\nMiscellaneous options:"

      opts.on_tail( "-h", "--help", "Show this usage message and exit.") do
        info( opts.help + "\n")
        exit
      end

      opts.on_tail( "--copyright", "Print the copyright.") do
        STDOUT.puts LICENSE
        exit
      end
    end
  end # build_option_parser

  def error( msg, with_status = nil)
    msg = "\n" + msg unless options[:verbose]
    STDERR.puts msg + " "
    exit with_status unless with_status.nil?
    exit
  end

  def warn( msg)
    msg = "\n" + msg unless options[:verbose]
    STDERR.puts msg + " "
  end

  def info( msg, compl = nil)
    if @options[ :verbose]
      msg = "%s → %s" % [ msg, compl] unless compl.nil? or compl.empty?
      msg += "\n" unless msg[ -1] == "\n"
    else
      msg += " " unless msg[ -1] == "\n"
    end
    STDOUT.print msg
  end

end
