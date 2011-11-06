#! /usr/bin/env ruby
# -*- encoding: utf-8 -*-

# Commande l'extraction des métadonnées d'une série d'images DICOM d'un dossier
# (ou d'une hiérarchie de dossiers) et leur conversion au format CSV.
#
# Usage:
#   ./dcm-export.rb [OPTIONS] DICOM_BASE_DIR
#
# Exemple:
#   ./dcm-export.rb --force test/valid-dicom/
#
# Pour un détail des options:
#   ./dcm-export.rb --help    .
#
# Prérequis:
#   ruby 1.9, et quelques gems (voir les fichiers Gemfile et README).
#
# Author:: Olivier Lange (mailto:olange@petit-atelier.ch)
# Copyright:: (c) 2011 Tristan Zand & Olivier Lange
# License:: GNU GPL, either v3 or (at your option) any later version.

require 'dicom'
require_relative 'lib/exam_cruncher'

DICOM.logger.level = Logger::FATAL

unless ENV['NO_RUN']
  ExamCruncher.crunch ARGV
end
