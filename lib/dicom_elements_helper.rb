#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

# Author:: Olivier Lange (mailto:olange@petit-atelier.ch)
# Copyright:: (c) 2011 Tristan Zand & Olivier Lange
# License:: GNU GPL, either v3 or (at your option) any later version.

require 'dicom'

# Noms et valeurs possibles de quelques éléments de données DICOM
# qui nous intéressent.

module DICOMElementsHelper

  # -- Méthodes utilitaires

  # Compose et retourne le nom de colonne qui doit figurer dans
  # un en-tête CSV pour un élément DICOM désigné par son nom (tag).
  # Si le nom de l'élément ne figure pas dans le dictionnaire
  # du module DICOM, retourne inchangé ce nom d'élément.
  def self.csv_colname_for( element_tag)
    DICOM_ELEMENTS_DICT.has_key?( element_tag) \
      ? "#{element_tag} (#{DICOM_ELEMENTS_DICT[ element_tag][ 1]})" \
      : "#{element_tag}"
  end

  # -- Noms de quelques éléments DICOM

  # Dictionnaire de tous les éléments DICOM, avec leur nom et type
  DICOM_ELEMENTS_DICT = DICOM::Dictionary.load_data_elements()

  # Type de scanner; devrait toujours valoir 'CT' dans notre cas
  DICOM_MODALITY_TAG              = "0008,0060"
  DICOM_MODALITY_CSVNAME          = csv_colname_for DICOM_MODALITY_TAG
                                  # "0008,0060 (Modality)"

  # Type de l'image; contient trois valeurs séparées par des backslash '\',
  # telles que 'ORIGINAL\PRIMARY\AXIAL', 'ORIGINAL\PRIMARY\LOCALIZER'
  # ou 'DERIVED\SECONDARY\SCREEN SAVE'
  DICOM_IMAGE_TYPE_TAG            = "0008,0008"
  DICOM_IMAGE_TYPE_CSVNAME        = csv_colname_for DICOM_IMAGE_TYPE_TAG
                                  # "0008,0008 (Image Type)"

  # Description d'une série d'images
  DICOM_SERIES_DESCRIPTION_TAG     = "0008,103E"
  DICOM_SERIES_DESCRIPTION_CSVNAME = csv_colname_for DICOM_SERIES_DESCRIPTION_TAG
                                   # "0008,103E (Series Description)"

  # Mode d'acquisition d'une série d'images; p. ex. 'SCOUT MODE'
  # ou 'HELICAL SCAN'. Noter que cet élément n'est pas présent sur tous les
  # examens et qu'il est plus sûr de chercher si c'est une image « scout »
  # dans l'élément Image Type (voir DICOM_IMAGE_TYPE_TAG).
  DICOM_SCAN_OPTIONS_TAG          = "0018,0022"
  DICOM_SCAN_OPTIONS_CSVNAME      = csv_colname_for DICOM_SCAN_OPTIONS_TAG
                                  # "0018,0022 (Scan Options)"

  # Durée d'exposition de la tranche (en ms)
  DICOM_EXPOSURE_TIME_TAG     = "0018,1150"
  DICOM_EXPOSURE_TIME_CSVNAME = csv_colname_for DICOM_EXPOSURE_TIME_TAG
                                  # "0018,1150 (Exposure Time)"

  # Intensité du courant pendant l'acquisition
  DICOM_XRAY_TUBE_CURRENT_TAG     = "0018,1151"
  DICOM_XRAY_TUBE_CURRENT_CSVNAME = csv_colname_for DICOM_XRAY_TUBE_CURRENT_TAG
                                  # "0018,1151 (X-ray Tube Current)"

  # Filtre appliqué par le scanner aux tranches d'une série d'images;
  # p. ex. 'HEAD FILTER', 'BODY FILTER', etc.
  DICOM_FILTER_TYPE_TAG           = "0018,1160"
  DICOM_FILTER_TYPE_CSVNAME       = csv_colname_for DICOM_FILTER_TYPE_TAG
                                  # "0018,1160 (Filter Type)"

  # Distance physique relative entre la tranche correspondant à une image
  # et la tranche de la première image
  DICOM_SLICE_LOCATION_TAG        = "0020,1041"
  DICOM_SLICE_LOCATION_CSVNAME    = csv_colname_for DICOM_SLICE_LOCATION_TAG
                                  # "0020,1041 (Slice Location)"

  # Données du bitmap d'une image
  DICOM_PIXEL_GROUP_LEN_TAG       = "7FE0,0000"
  DICOM_PIXEL_GROUP_LEN_CSVNAME   = csv_colname_for DICOM_PIXEL_GROUP_LEN_TAG
                                  # "7FE0,0000" (ne possède pas de nom)

  DICOM_PIXEL_DATA_TAG            = "7FE0,0010"
  DICOM_PIXEL_DATA_CSVNAME        = csv_colname_for DICOM_PIXEL_DATA_TAG
                                  # "7FE0,0010 (Pixel Data)"

  # Pseudo-élément correspondant au nom du fichier source d'une image
  DICOM_SOURCE_FILE_TAG           = "DICOM Source File"
  DICOM_SOURCE_FILE_CSVNAME       = csv_colname_for DICOM_SOURCE_FILE_TAG
                                  # "DICOM Source File"

  # -- Valeurs possibles de quelques éléments

  # Valeurs possible de l'élément 0008,0008 (Image Type): expression
  # régulière permettant d'identifier une image « scout »
  DICOM_IMAGE_TYPE_SCOUT_MODE_RE  = /\\LOCALIZER/

end
