#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

# Author:: Olivier Lange (mailto:olange@petit-atelier.ch)
# Copyright:: (c) 2011 Tristan Zand & Olivier Lange
# License:: GNU GPL, either v3 or (at your option) any later version.

require 'dicom'
require 'stringio'
require_relative '../lib/exam'
require_relative '../lib/dicom_elements_helper'

# Spécifications de test RSpec2 de la classe Exam.
#
# Un jeu de fichiers DICOM de test accompagne ces spécifications, qui se trouve
# dans le sous-dossier <tt>test/</tt>, dont un aperçu est donné ci-après.
# Consulter le fichier README_test pour une description détaillée de ce
# jeu de test, des particularités des fichiers de chaque dossier.
#
# RSpec est un « domain specific language », qui permet d'exprimer les tests
# fonctionnels par des exemples, dans une forme réputée naturellement lisible.
# Cela vient au prix d'une certaine astuce et expérience! Pour une explication
# sur l'un des idiomes de RSpec, consulter http://relishapp.com/rspec.

describe Exam do

  include DICOMElementsHelper

  before( :all) do
    DICOM.logger.level = Logger::FATAL

    BASE_INPUT_DIR = "test"
    BASE_OUTPUT_DIR = "test"

    INPUT_DIR = "#{BASE_INPUT_DIR}/valid-dicom/LAPIN2_PRO_APC_100KV_CTDIVOL8_6"
    OTHER_INPUT_DIR = "#{BASE_INPUT_DIR}/valid-dicom/LAPIN2_PRO_APC_140KV_CTDIVOL2_16"
    ANOTHER_INPUT_DIR = "#{BASE_INPUT_DIR}/valid-dicom/Rapport_dose_999"

    DIR_WITH_LOCALIZERS_ONLY = "#{BASE_INPUT_DIR}/valid-dicom/Localizers_1"
    DIR_WITH_NO_DICOM = "#{BASE_INPUT_DIR}/no-dicom"
    DIR_WITH_CORRUPT_DICOM = "#{BASE_INPUT_DIR}/invalid-dicom"
    DIR_WITH_MIXED_CONTENT = "#{BASE_INPUT_DIR}/mixed-content"
    DIR_WITH_NON_HOMOGENEOUS_CONTENT = "#{BASE_INPUT_DIR}/non-homogeneous"

    OUTPUT_CSV = "#{BASE_OUTPUT_DIR}/exam-lapin2-100kv.csv"
    OTHER_OUTPUT_CSV = "#{BASE_OUTPUT_DIR}/exam-lapin2-140kv.csv"
  end

  # On suppose que le sous-dossier <tt>./test</tt> contient cinq jeux de fichiers
  # dans la hiérarchie de dossiers et le nombre de fichiers suivants:
  #
  # * <tt>test/valid-dicom/LAPIN2_PRO_APC_100KV_CTDIVOL8_6/</tt> 15 fichiers .DCM
  # * <tt>test/valid-dicom/LAPIN2_PRO_APC_140KV_CTDIVOL2_16/</tt> 10 fichiers .DCM
  # * <tt>test/valid-dicom/Localizers_1/</tt> 2 fichiers .DCM
  # * <tt>test/valid-dicom/Rapport_dose_999/</tt> 2 fichiers .DCM
  # * <tt>test/mixed-content/</tt> 4 fichiers .DCM, dont l'un est
  #     un fichier texte, et un autre fichier texte sans extension
  # * <tt>test/non-homogeneous/</tt> 6 fichiers .DCM provenant de 3 séries
  #     d'images différentes, ayant une structure de données différente
  # * <tt>test/invalid-dicom/</tt> 1 fichier .DCM corrompu
  # * <tt>test/no-dicom</tt> aucun fichier .DCM
  #
  # Consulter le fichier <tt>test/README.test</tt> pour une description plus
  # détaillée de ce jeu de test, des particularités des fichiers de chaque dossier.
  it 'test has the expected fileset' do
    Dir.glob( INPUT_DIR + "/*.dcm").should have(15).entries
    Dir.glob( OTHER_INPUT_DIR + "/*.dcm").should have(10).entries
    Dir.glob( ANOTHER_INPUT_DIR + "/*.dcm").should have(2).entries
    Dir.glob( DIR_WITH_LOCALIZERS_ONLY + "/*.dcm").should have(2).entries
    Dir.glob( DIR_WITH_NO_DICOM + "/*.dcm").should have(0).entries
    Dir.glob( DIR_WITH_CORRUPT_DICOM + "/*.dcm").should have_at_least(1).entries
    Dir.glob( DIR_WITH_MIXED_CONTENT + "/*.dcm").should have(4).entries
    Dir.glob( DIR_WITH_MIXED_CONTENT + "/README*").should have(1).entries
    Dir.glob( DIR_WITH_NON_HOMOGENEOUS_CONTENT + "/*.dcm").should have(6).entries
  end

  context 'in the normal case' do

    it 'would read from the source path given' do
      # Affectation
      exam = Exam.new INPUT_DIR, :defer_loading => true
      exam.source_dir.should == INPUT_DIR

      # Réaffectation
      exam.source_dir = OTHER_INPUT_DIR
      exam.source_dir.should == OTHER_INPUT_DIR
    end

    it 'normalizes the directory path' do
      exam1 = Exam.new "#{INPUT_DIR}//", :defer_loading => true
      exam1.source_dir.should == INPUT_DIR  # trailing separators should have been removed

      exam2 = Exam.new "#{INPUT_DIR}/IM-0001-0001.dcm", :defer_loading => true
      exam2.source_dir.should == INPUT_DIR  # file component should have been removed
    end

    it 'reads a set of valid DICOM files from a directory' do
      exam = Exam.new INPUT_DIR, :defer_loading => true
      exam.should be_empty
      exam.images.should be_empty
      exam.scouts.should be_empty
      exam.read_images
      exam.should_not be_empty
      exam.should have_images
      exam.should_not have_scouts
      exam.images.should have(15).items
      exam.scouts.should be_empty

      path, dobject = exam.images.first
      path.should match Regexp.new( INPUT_DIR + "/[^.]+\\.dcm")
      dobject.exists?( DICOM_XRAY_TUBE_CURRENT_TAG).should be_true
      dobject.exists?( DICOM_SLICE_LOCATION_TAG).should be_true
      xray, loc = nil, nil
      expect { xray = \
        Float( dobject[ DICOM_XRAY_TUBE_CURRENT_TAG].value) } \
          .to_not raise_error
      expect { loc = \
        Float( dobject[ DICOM_SLICE_LOCATION_TAG].value) } \
          .to_not raise_error
      xray.should == 175.0
      (56.125..68.0).should cover( loc)
    end

    it 'automatically identifies scout images' do
      exam = Exam.new DIR_WITH_LOCALIZERS_ONLY
      exam.should_not be_empty
      exam.should_not have_images
      exam.should have_scouts
      exam.images.should be_empty
      exam.scouts.should have(2).items
    end

    it 'automatically extracts the name from the exam images' do
      exam1 = Exam.new INPUT_DIR
      exam1.name.should == "LAPIN2 PRO APC 100KV CTDIVOL8"

      exam2 = Exam.new OTHER_INPUT_DIR
      exam2.name.should == "LAPIN2 PRO APC 140KV CTDIVOL2"

      exam3 = Exam.new DIR_WITH_LOCALIZERS_ONLY
      exam3.name.should == "LAPIN 2 PRO"

      exam4 = Exam.new DIR_WITH_NO_DICOM
      exam4.name.should == "(empty image set)"
    end

    it 'detects variant structure of the DICOM files' do
      # Cas de série d'images avec structure non homogène
      exam1 = Exam.new DIR_WITH_NON_HOMOGENEOUS_CONTENT
      exam1.should_not have_homogeneous_structure

      # Cas de série d'images avec structure homogène
      exam2 = Exam.new INPUT_DIR
      exam2.should have_homogeneous_structure

      exam3 = Exam.new ANOTHER_INPUT_DIR
      exam3.should have_homogeneous_structure

      # Cas particulier: si images « scout » uniquement, la « structure »
      # des images (absentes!) est considérée comme homogène également
      exam4 = Exam.new DIR_WITH_LOCALIZERS_ONLY
      exam4.should have_homogeneous_structure
    end

  end

  context 'for alternative cases' do

    it 'invalidates the image data already extracted when the source directory changes' do
      exam = Exam.new INPUT_DIR, :defer_loading => true
      exam.read_images
      exam.images.should have_at_least(1).item

      # No effective change
      current_source_dir = exam.source_dir
      expect{ exam.source_dir = current_source_dir }.to_not change{ exam.images }
      expect{ exam.source_dir = current_source_dir }.to_not change{ exam.scouts }

      # Effective change
      exam.source_dir = OTHER_INPUT_DIR
      exam.source_dir.should == OTHER_INPUT_DIR
      exam.images.should be_empty   # attention! test possible parce que :defer_loading = true
      exam.scouts.should be_empty   # (sinon contenu de OTHER_INPUT_DIR aurait été chargé)
    end

    it 'still behaves when the source directory contains no DICOM images at all' do
      exam = Exam.new DIR_WITH_NO_DICOM, :defer_loading => true
      expect { exam.read_images }.to_not raise_error
      exam.should be_empty
      exam.should_not have_images
      exam.should_not have_scouts
    end

    it 'picks DICOM files from a directory also containing non-DICOM files' do
      exam = Exam.new DIR_WITH_MIXED_CONTENT, :defer_loading => true
      expect { exam.read_images }.to_not raise_error
      exam.name.should == "LAPIN2 PRO APC 140KV CTDIVOL2" # extrait de @images et non de @scout
      exam.images.should have(2).items
      exam.scouts.should have(1).items
      # Les deux tests ci-dessus établissent également que seuls trois
      # fichiers DICOM ont été lus, partant que le fichier texte avec
      # l'extension '.dcm' a bien été ignoré.
    end

  end

  context 'when DICOM files are invalid' do

    it 'raises an exception while reading' do
      exam = Exam.new DIR_WITH_CORRUPT_DICOM, :defer_loading => true
      expect { exam.read_images }.to raise_error( /fichier corrompu/)
    end

  end

  context 'when exporting to CSV' do

    it 'builds a CSV header with correct number of fields' do
      # Images DICOM du premier examen contiennent 225 éléments
      # de métadonnées (hors Pixel Data, qui a été supprimé)
      exam1 = Exam.new INPUT_DIR
      header_cols1 = exam1.csv_metadata_header
      header_cols1.should have(226).items   # = 225 élts DICOM + 1 nom fichier

      # Eléments génériques
      header_cols1.first.should == DICOM_SOURCE_FILE_CSVNAME
      header_cols1.should include DICOM_MODALITY_CSVNAME
      header_cols1.last.should == DICOM_PIXEL_GROUP_LEN_CSVNAME

      # Eléments spécifiques qui nous intéressent
      header_cols1.should include DICOM_XRAY_TUBE_CURRENT_CSVNAME
      header_cols1.should include DICOM_SLICE_LOCATION_CSVNAME

      # Images DICOM du rapport de dose contiennent 67 éléments de métadonnées,
      # dont sont absents les éléments spécifiques "0018,1151" et "0020,1041"
      exam2 = Exam.new ANOTHER_INPUT_DIR
      header_cols2 = exam2.csv_metadata_header
      header_cols2.should have(68).items
      header_cols1.first.should == DICOM_SOURCE_FILE_CSVNAME
      header_cols2.should include DICOM_MODALITY_CSVNAME
      header_cols1.last.should == DICOM_PIXEL_GROUP_LEN_CSVNAME
      header_cols2.should_not include DICOM_XRAY_TUBE_CURRENT_CSVNAME
      header_cols2.should_not include DICOM_SLICE_LOCATION_CSVNAME

      # Les images « scout » ne doivent pas être prises en compte par l'export CSV
      exam3 = Exam.new DIR_WITH_LOCALIZERS_ONLY
      header_cols3 = exam3.csv_metadata_header
      header_cols3.should be_empty
    end

    it 'exports the DICOM files metadata to one CSV file (which should have a header)' do
      # Commande l'export CSV des deux examens 100KV et 140KV
      # ('X-ray Tube Current' tantôt constant, tantôt variant)
      exam1 = Exam.new INPUT_DIR
      exam1.sort_images_by! :slice_location
      open( OUTPUT_CSV, "w") { |file| exam1.to_csv file }

      exam2 = Exam.new OTHER_INPUT_DIR
      exam2.sort_images_by! :slice_location
      open( OTHER_OUTPUT_CSV, "w") { |file| exam2.to_csv file }

      # Vérifie que les fichiers CSV ont été créés
      expect { File.file? OUTPUT_CSV }.to be_true
      expect { File.file? OTHER_OUTPUT_CSV }.to be_true

      # Vérifie qu'on peut bien relire les données CSV (la méthode CSV.read
      # retourne le contenu du fichier CSV sous forme de tableau à 2 dimensions)
      datasheet = CSV.read( OUTPUT_CSV, Exam::DEFAULT_CSV_OPTIONS)  # maousse!
      datasheet.should have( 16).lines      # 1 ligne d'en-tête + 15 de données
      datasheet[ 0].should have( 226).items # ligne de l'en-tête CSV
      datasheet[ 1].should have( 226).items # première ligne de données
      datasheet[15].should have( 226).items # dernière ligne de données

      # Et qu'on y trouve les mêmes valeurs que dans l'examen original
      csv_header = datasheet[ 0]
      source_filenam_col = csv_header.index( DICOM_SOURCE_FILE_CSVNAME)
      source_filenam_col.should be_zero
      xray_intensity_col = csv_header.index( DICOM_XRAY_TUBE_CURRENT_CSVNAME)
      xray_intensity_col.should_not be_nil
      slice_location_col = csv_header.index( DICOM_SLICE_LOCATION_CSVNAME)
      slice_location_col.should_not be_nil

      exam_paths = exam1.images.keys
      exam_dobjects = exam1.images.values
      datasheet[ 1][ source_filenam_col].should == exam_paths[ 0]
      datasheet[ 1][ xray_intensity_col].should \
        == exam_dobjects[ 0][ DICOM_XRAY_TUBE_CURRENT_TAG].value
      datasheet[ 1][ slice_location_col].should \
        == exam_dobjects[ 0][ DICOM_SLICE_LOCATION_TAG].value
      datasheet[15][ source_filenam_col].should == exam_paths[14]
      datasheet[15][ xray_intensity_col].should \
        == exam_dobjects[14][ DICOM_XRAY_TUBE_CURRENT_TAG].value
      datasheet[15][ slice_location_col].should \
        == exam_dobjects[14][ DICOM_SLICE_LOCATION_TAG].value
    end

    it 'reports variant structure of the DICOM files when exporting to CSV' do
      exam = Exam.new DIR_WITH_NON_HOMOGENEOUS_CONTENT
      StringIO.open( "/dev/null", "w") do |file|
        expect { exam.to_csv file } \
          .to raise_error( /inconsistent structure/)
      end
    end

    it 'correctly sorts the images according to location, if asked' do
      # Sans tri, les images sont communément dans ordre indéfini
      # de 'Slice Location' (quoique cela dépende de Dir.glob, qui
      # retourne les noms des fichiers selon ordre indéfini et qui
      # pourrait exceptionnellement correspondre à l'ordre de tri)
      exam1 = Exam.new INPUT_DIR, :sort_images_by => nil
      expect { exam1.images.values \
        .map { |dobj| Float( dobj[ DICOM_SLICE_LOCATION_TAG].value) } \
        .each_cons( 2) { |loc1, loc2| \
          throw :unordered_images, "location #{loc1} found before #{loc2}" \
            unless loc1 <= loc2 }
      }.to throw_symbol( :unordered_images)

      # Avec tri des images, selon valeur de leur élément 'Slice Location'
      exam2 = Exam.new INPUT_DIR, :sort_images_by => :slice_location
      expect { exam2.images.values \
        .map { |dobj| Float( dobj[ DICOM_SLICE_LOCATION_TAG].value) } \
        .each_cons( 2) { |loc1, loc2| \
          throw :unordered_images, "location #{loc1} found before #{loc2}" \
            unless loc1 <= loc2 }
      }.to_not throw_symbol( :unordered_images)
    end

  end

end
