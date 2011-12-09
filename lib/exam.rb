#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

# Author:: Olivier Lange (mailto:olange@petit-atelier.ch)
# Copyright:: (c) 2011 Tristan Zand & Olivier Lange
# License:: GNU GPL, either v3 or (at your option) any later version.

require 'dicom'
require 'csv'
require_relative 'dicom_elements_helper'
require_relative 'graph_template.html'

# Lit un jeu d'images DICOM d'un examen radiologique de type CTscan
# à partir d'un dossier source, en distinguant les images « scout »
# des images de l'examen lui-même. Permet d'extraire les métadonnées
# du jeu d'images de l'examen et de les exporter au format CSV.
#
# Le dossier source peut contenir un jeu de fichiers hétérogènes,
# par exemple texte et images DICOM. Les fichiers images DICOM sont
# identifiés par lecture et analyse de leur en-tête.
#
# Usage courant, pour exporter les métadonnées:
#
#   exam = Exam.new( "images/exam001/")
#   open( "exam001.csv", "w+") do |file|
#     exam.to_csv( file)
#   end
#
# Pour investiguer le jeu d'images d'un examen:
#
#   exam = Exam.new( "images/exam001/")
#   exam.read_images
#   puts exam.name
#   puts exam.images.keys
#   puts exam.scouts.keys
#
# Noter que le jeu d'images demeure invariant une fois que les images ont été
# chargées par l'invocation de la méthode read_images; des appels subséquents
# n'ont plus d'effet.
#
# En changeant la valeur de la variable d'instance source_dir, il est
# cependant possible de forcer une réinitialisation et de réutiliser un
# objet Exam; si sa valeur change effectivement, il faut alors invoquer
# à nouveau la méthode read_image.
#
# Nomenclature des noms de variables:
#
# * +image+: désigne un tuple <tt>'PATH' => DICOM::DObject</tt>.
# * +scout+: idem, désigne un tuple <tt>'PATH' => DICOM::DObject</tt>.
# * +dobject+: désigne un objet <tt>DICOM::DObject</tt>.
# * +path+: désigne le plus souvent un chemin d'accès à un fichier source DICOM.

class Exam
  include DICOMElementsHelper

  # Dossier source dans lequel se trouvent les images DICOM à traiter
  attr_accessor :source_dir

  # Options d'extraction; voir DEFAULT_OPTIONS pour les valeurs possibles.
  attr_reader :options_extract

  # Collection des images de l'examen (<tt>'PATH' => DICOM::DObject</tt>).
  #
  # Il s'agit d'un hash, dont la _clé_ est le chemin d'accès (path) au
  # fichier source et la _valeur_ est l'objet DICOM correspondant, obtenu
  # par le décodage du fichier source.
  #
  # Pour extraire et traiter un élément, voici quelques idiomes valides:
  #
  #   path, dobject = exam.images[1]
  #   path, dobject = exam.images.first
  #   dobject = exam.images[ '<PATH>']
  #   dobject = exam.images.values[ INDEX]
  #   exam.images.each { |path, dobject| ... }
  #   exam.images.each_value { |dobject| ... }
  #
  # Noter que dans les deux premiers exemples, on accède de façon
  # _positionnelle_ à un élément du hash (non par la clé). Dans ce cas,
  # un hash Ruby retourne un <em>tableau avec deux éléments</em>, le premier
  # contenant la clé (path) et le second contenant la valeur (l'objet DICOM).
  attr_reader :images

  # Collection des « images scout » de l'examen (<tt>'PATH' => DICOM::DObject</tt>).
  # Ces images, également désignées « localizers », présentent une vue
  # d'ensemble transversale correspondant aux images de l'examen.
  # Il s'agit d'un hash de structure semblable à celle de la
  # collection +images+.
  attr_reader :scouts

  # Nom de l'examen (composé d'après la description du jeu d'images,
  # voir méthode extract_exam_name)
  attr_reader :name

  # Options d'extraction par défaut
  DEFAULT_OPTIONS = {
    # Chargement immédiat ou différé des images lors définition source_dir=
    :defer_loading => false,    # false: charge immédiatement les images
    # Réordonnancement des images après chargement
    :sort_images_by => nil      # false ou nil, pas de tri; :slice_location,
  }                             # tri selon position de l'image dans la série

  # Paramètres de conversion CSV par défaut (voir description du module CSV)
  DEFAULT_CSV_OPTIONS = {
    :col_sep => ',', :quote_char => '"', :force_quotes => true
  }

  # Créé un nouvel examen à partir du jeu d'images DICOM qui se trouve
  # dans un dossier source. Si aucun dossier n'est comuniqué, il pourra
  # l'être ultérieurement en invoquant la méthode source_dir=
  def initialize( dir_path = nil, options = {})
    reset!
    @options_extract = DEFAULT_OPTIONS.merge( options)
    self.source_dir = dir_path
  end

  # Définit le chemin d'accès au dossier source, qui contient le jeu
  # d'images DICOM à traiter.
  #
  # Commande ensuite le chargement des images du dossier source
  # (en invoquant la méthode read_images) -- à moins que l'option
  # :defer_loading ne contienne true, dans quel cas le chargement
  # doit être commandé par une invocation explicite de read_images.
  #
  # S'il y en avait déjà, commande auparavant l'effacement des images
  # qui étaient en mémoire.
  #
  # Retourne le chemin d'accès effectivement mémorisé, après normalisation.
  def source_dir=( dir_path)
    return if dir_path.nil? or @source_dir == dir_path
    reset!    # clear all data as source directory changed
    @source_dir = remove_last_dir_sep_from dir_path
    read_images unless @options_extract[ :defer_loading]
    @source_dir
  end

  # Retourne true si les fichiers des images DICOM ont été intégralement lus
  # (dans quel cas @images et/ou @scouts contiennent des éléments)
  def images_already_read?
    @images_read  # comprendre @images_read == true, mais ne pas l'écrire!
  end             # (cf. Eloquent Ruby, chap. 2, p.22)

  # Lecture de toutes les images DICOM qui se trouvent dans le dossier
  # source (qui doit évidemment avoir été défini, utiliser la méthode
  # source_dir= pour ce faire). Retourne le nombre d'images lues ou
  # +nil+ si les images ont déjà été lues plus tôt.
  #
  # Soulève une exception RuntimeError avec un message, si l'objet DICOM
  # n'a pas pu être créé, le fichier source ne peut pas être analysé
  # ou que la modalité n'est pas 'CT'.
  def read_images
    return if images_already_read?

    image_files = find_images_in @source_dir
    image_files.each do |path|
      dobject = DICOM::DObject.read path
      assert_is_kind_of_dobject dobject if dobject.nil? # the paranoïd freak in me
      assert_successfully_read path, dobject
      assert_modality_is_CTscan path, dobject
      dobject.remove( DICOM_PIXEL_DATA_TAG)  # pour diminuer l'empreinte mémoire
      @images[ path] = dobject
    end
    @images_read = true

    # NOTE: éxécuter prune_scout_images_from!() avant extract_exam_name(),
    # afin d'extraire le nom en priorité à partir des images de l'examen
    @scouts = prune_scout_images_from! @images
    @name = extract_exam_name

    sort_images_by! options_extract[:sort_images_by] \
      if options_extract[:sort_images_by]

    @images.count + @scouts.count
  end

  # Retourne +true+ si une image DICOM au moins a été extraite du dossier
  # source, +false+ dans le cas contraire et +nil+ si aucun fichier n'a
  # encore été lu.
  def has_images?
    @images && @images.count > 0
  end

  # Retourne +true+ si une image DICOM de type _scout_ au moins a été extraite
  # du dossier source, +false+ dans le cas contraire et +nil+ si aucun fichier
  # n'a encore été lu.
  def has_scouts?
    @scouts && @scouts.count > 0
  end

  # Retourne +false+ si une image DICOM de type quelconque (normale ou _scout_)
  # au moins a été trouvée dans le dossier source, +true+ dans le cas contraire
  # et +nil+ si aucun fichier n'a encore été lu.
  def empty?
    return nil if @images.nil? and @scouts.nil?
    not( has_images? or has_scouts?)
  end

  # Retourne true si la structure de données de toutes les images
  # est homogène (ou qu'il n'y a aucune image), false sinon.
  def has_homogeneous_structure?
    # Si déjà interrogé plus tôt, on s'épargne un recalcul
    return @images_homogeneous unless @images_homogeneous.nil?

    # Sinon on examine la structure des images, deux par deux
    homogeneous = true
    prev_struct, struct = nil, nil
    @images.each_value do |dobject|
      prev_struct, struct = struct, sign_structure_of( dobject)
      next if prev_struct.nil? or( struct == prev_struct)
      homogeneous = false; break
    end
    @images_homogeneous = homogeneous

    # Plus succinct?
    # @images.map { |path,dobj| sign_structure_of dobj }.each_cons(2) \
    #   { |sig1,sig2| next if sig1 == sig2; homogeneous = false; break }
  end

  # Retourne une copie des images réordonnées selon l'argument +order+:
  #
  # * s'il vaut +:slice_location+, réordonne les images selon
  #   la position de la tranche que chacune représente, c-à-d.
  #   la valeur de l'élément "0020,1041 (Slice Location)";
  #
  # * s'il vaut +false+, +nil+ ou tout autre valeur, retourne
  #   la collection d'images inchangée.
  def sort_images_by( order = :slice_location)
    return {} if @images.empty?
    case order
      when :slice_location
        sorted_hash = {}
        sorted_array = @images.sort_by do |path, dobject|
          dobject.exists?( DICOM_SLICE_LOCATION_TAG) \
            ? Float( dobject[ DICOM_SLICE_LOCATION_TAG].value) \
            : -Float::INFINITY  # images sans Slice Location: tout au début
        end
        sorted_array.each { |path, dobject| sorted_hash[ path] = dobject }
        sorted_hash
      else
        @images
    end
  end

  # Identique à sort_images_by, si ce n'est que les images de l'examen
  # sont réordonnées « in place ».
  def sort_images_by!( order = :slice_location)
    @images = sort_images_by order
  end

  # Retourne un tableau contenant les noms des colonnes qui se trouveraient
  # dans l'en-tête du fichier CSV lorsque l'on exporte les métadonnées
  # (voir la méthode to_csv). Exemple de fragment de tableau retourné:
  #   [ ..., "0010,0000 (Group Length)", "0010,0010 (Patient's Name)", ... ]
  def csv_metadata_header
    return [] if @images.empty?
    csv_metadata_header_from @images.first
  end

  # Transcrit les métadonnées d'une image DICOM dans un fichier CSV.
  #
  # Le paramètre 'output_file' doit contenir un _objet_ fichier dans
  # lequel il est possible d'écrire (non seulement le nom d'un fichier).
  #
  # Soulève une exception RuntimeError si la structure des images n'est
  # pas homogène (ce qui signale plusieurs séries d'images différentes).
  def to_csv( output_file)
    read_images
    return if @images.empty?
    raise "DICOM source files have inconsistent structure among them" \
      unless has_homogeneous_structure?

    csv_options = DEFAULT_CSV_OPTIONS
    CSV( output_file, csv_options) do |csv_file|
      csv_file << csv_metadata_header
      sort_images_by( :slice_location).each do |image|
        csv_file << csv_metadata_values_from( image)
      end
    end
  end

  def to_html( output_file)
    read_images
    return if @images.empty?
    raise "DICOM source files have inconsistent structure among them" \
      unless has_homogeneous_structure?

    data = []
    sort_images_by( :slice_location).values.each do |dobject|
      data << {
        :l => dobject.exists?( DICOM_SLICE_LOCATION_TAG) \
          ? Float( dobject[ DICOM_SLICE_LOCATION_TAG].value) : 0.0,
        :x => dobject.exists?( DICOM_XRAY_TUBE_CURRENT_TAG) \
          ? Float( dobject[ DICOM_XRAY_TUBE_CURRENT_TAG].value) : 0.0,
        :t => dobject.exists?( DICOM_EXPOSURE_TIME_TAG) \
          ? Float( dobject[ DICOM_EXPOSURE_TIME_TAG].value) : 0.0
      }
    end
    output_file << html_graph_for( data, @name)
  end

  private

  # Réinitialise les variables d'instance à une valeur neutre.
  # Invoqué lorsque le chemin d'accès du dossier source change.
  def reset!
    @source_dir = nil
    @name = "(no name)"
    @images_read = false
    @images_homogeneous = nil
    @images = @images.nil? ? {} : @images.clear
    @scouts = @scouts.nil? ? {} : @scouts.clear
  end

  # Normalise le chemin d'accès à un dossier, en éliminant le dernier séparateur
  # de dossier s'il est présent et un éventuel nom de fichier. Par exemple,
  # retourne "test" pour les chemins d'accès "test", "test/" et "test/image.dcm".
  def remove_last_dir_sep_from( path)
    File.file?( path) ? File.dirname( path) : File.dirname( path + "/.")
  end

  # Pattern des fichiers DICOM contenus dans un dossier donné, susceptible
  # d'être communiqué à Dir.glob()
  def image_files_pattern_for( dir_path)
    "#{dir_path}/*"
  end

  # Retourne true si le chemin d'accès donné est un fichier susceptible
  # d'être une image DICOM, false sinon. Recherche une signature DICOM
  # valide dans les premiers octets du fichier pour ce faire.
  def candidate_image?( file_path)
    File.file?( file_path) and looks_like_dicom?( file_path)
  end

  # Retourne true si la signature 'DICM' se trouve à l'emplacement
  # du 128ème octet du fichier (pour un aperçu de l'anatomie d'un
  # fichier DICOM, consulter http://www.cabiatl.com/mricro/dicom/)
  def looks_like_dicom?( file_path)
    chars = ""
    open( file_path) do |file|
      file.pos = 128
      chars = file.read 4
    end
    chars == 'DICM'
  end

  # Retourne un tableau avec le nom de tous les fichiers qui se trouvent
  # dans un dossier et qui sont susceptibles d'être des images DICOM
  def find_images_in( source_dir)
    image_files = []
    Dir.glob( image_files_pattern_for @source_dir) do |path|
      image_files << path if candidate_image?( path)
    end
    image_files
  end

  # Soulève une exception si l'objet n'est pas compatible avec DICOM::DObject
  def assert_is_kind_of_dobject( obj)
    raise TypeError, "Expected a DICOM::DObject, got #{obj.class}" \
      unless obj.kind_of? DICOM::DObject
  end

  # Soulève une exception si l'objet DICOM n'a pu être que partiellement
  # renseigné lors de la lecture du fichier source DICOM
  def assert_successfully_read( path, dobject)
    raise "Image DICOM non traitée: #{path}; fichier corrompu?" \
      unless dobject.read_success
  end

  # Soulève une exception si l'image ne provient pas d'un scanner de type 'CT'
  def assert_modality_is_CTscan( path, dobject)
    modality = dobject[ DICOM_MODALITY_TAG].value
    raise "Image DICOM de type autre que 'CT': #{path}, type: #{modality}" \
      unless modality == "CT"
  end

  # Retourne une signature de la structure d'un objet DICOM, sous forme de chaîne
  # de caractères. Cette signature doit être différente pour deux objets DICOM
  # ayant une hiérarchie ou un nombre d'éléments DICOM distincts.
  def sign_structure_of( dobject)
    assert_is_kind_of_dobject dobject
    dobject.elements.map { |elt| elt.tag }.join( "/")
  end

  # Détermine et retourne le nom de l'examen tantôt à partir des images
  # de l'examen s'il y en a, ou des images _scout_ s'il n'y en a pas.
  # Retourne une valeur par défaut s'il n'y a ni image normale ni _scout_.
  def extract_exam_name
    return extract_exam_name_from( @images.first) unless @images.first.nil?
    return extract_exam_name_from( @scouts.first) unless @scouts.first.nil?
    "(empty image set)"  # valeur par défaut
  end

  # Détermine et retourne le nom de l'examen à partir des métadonnées
  # d'une image DICOM; extrait pour ce faire la valeur de l'élément
  # <em>Series Description</em> (tag <tt>0008,103E</tt>).
  def extract_exam_name_from( image)
    path, dobject = image
    dobject[ DICOM_SERIES_DESCRIPTION_TAG].value
  end

  # Retourne true si l'objet DICOM contient une image _scout_, en vérifiant
  # si la valeur 'LOCALIZER' est présente dans l'élément 'Image Type'.
  # Attention, entorse à la nomenclature dans le nom de la méthode:
  # on attend un objet DICOM::DObject comme argument.
  def is_scout_image?( dobject)
    assert_is_kind_of_dobject dobject
    dobject.exists?( DICOM_IMAGE_TYPE_TAG) \
      and dobject[ DICOM_IMAGE_TYPE_TAG].value =~ DICOM_IMAGE_TYPE_SCOUT_MODE_RE
  end

  # Supprime et retourne toutes les images _scout_ d'une collection
  # d'images donnée. Attention: la collection passée en paramètre sera
  # altérée si elle contient des images _scout_.
  def prune_scout_images_from!( images)
    scouts = images.select { |path, dobject| is_scout_image? dobject }
    scouts.each_key { |path| images.delete path } unless scouts.empty?
    scouts  # contient au moins {}
  end

  # Retourne un tableau constitué de l'identifiant (tag) et du nom de chaque
  # élément d'une image DICOM, destiné à être utilisé pour former l'en-tête
  # d'un fichier CSV. Exemple de fragment de tableau retourné:
  #   [ ..., "0010,0000 (Group Length)", "0010,0010 (Patient's Name)", ... ]
  def csv_metadata_header_from( image)
    path, dobject = image
    dobject.elements.map { |elt| \
      DICOMElementsHelper::csv_colname_for elt.tag } \
        .insert( 0, DICOM_SOURCE_FILE_CSVNAME)
  end

  # Retourne un tableau avec la valeur de tous les éléments (métadonnées)
  # d'une image DICOM, destinés à être exportés dans un fichier CSV.
  def csv_metadata_values_from( image)
    path, dobject = image
    dobject.elements.map { |elt| elt.value }.insert( 0, path)
  end

end
