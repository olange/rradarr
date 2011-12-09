#! /usr/bin/env ruby
# -*- encoding: utf-8 -*-

# Author:: Olivier Lange (mailto:olange@petit-atelier.ch)
# Copyright:: (c) 2011 Tristan Zand & Olivier Lange
# License:: GNU GPL, either v3 or (at your option) any later version.

require 'json/ext'

# Retourne un document HTML permettant de tracer un histogramme à partir
# d'un ensemble de coordonnées <Slice location, X-ray tube current,
# Exposure time, Content time>.
#
# Le jeu de données doit être communiqué sous forme d'un tableau de
# coordonnées, où chaque coordonnée est un hash de la forme suivante:
#
#   { :sl => FLOAT, :xr => FLOAT, :et => FLOAT, :ct => FLOAT }.
#
# Par exemple:
#
#   [ { :sl => 59.25, :xr => 175.0, :et => 400.0, :ct => 183213.0}, ... ]
def html_graph_for( data, title)
  return BARGRAPH_TEMPLATE \
    % { :graph_data => data.to_json, :graph_title => title }
end

# Modèle de document HTML avec script D3.js pour tracer histogramme.
# Contient les marqueurs %{graph_title} et %{graph_data}, qui doivent
# être remplacés par leurs valeurs effectives (cf. html_graph_for).
BARGRAPH_TEMPLATE = <<EOF
<!doctype html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
    <title>rradarr &middot; Histogramme de l'exposition</title>
    <script type="text/javascript" src="http://mbostock.github.com/d3/d3.js"></script>
    <script type="text/javascript">
    // Trace un histogramme SVG à partir d'un ensemble de coordonnées
    // rectilignes <X,Y1,Y2> (X: abscisse/libellé et Yx: ordonnée/valeur
    // de l'un des points du graphe).
    //
    // title: titre du graphe, qui sera inscrit sous l'axe X.
    //
    // data: tableau de valeurs <X,Y1,Y2...>
    //   par exemple: [ { loc: 66.125, xray: 140.0 }, ... ]
    //
    // attr_x: accesseur permettant de lire la valeur X à partir d'une
    //   entrée du tableau de valeurs; par exemple:
    //   function( d) { return d.loc; }
    //
    // attr_y: accesseur permettant de lire la valeur Y à partir d'une
    //   entrée du tableau de valeurs; par exemple:
    //   function( d) { return d.xray; }
    //
    // width: largeur intérieure du graphe, en pixels; par exemple: 960.
    //
    // height: hauteur intérieure du graphe, en pixels; par exemple: 480.
    //
    // m: marges du graphe; il doit s'agir d'un objet, qui doit posséder
    //   les attributs top, bottom, left et right; par exemple:
    //   { top: 10, right: 5, bottom: 10, left: 5 }
    //
    // Noter que la largeur totale du graphe est width + m.left + m.right
    // et que sa hauteur est height + m.top + m.bottom.
    function draw_area_graph( title, data, attr_x, attr_y, width, height, m) {
      var TICK_COUNT = 10;

      var data_extent_x = d3.extent( data, attr_x),   // p. ex. [ 59.2, 68]
          data_extent_y = d3.extent( data, attr_y),   // p. ex. [ 120, 175]

          scale_x = d3.scale.linear()
            .domain( data_extent_x).nice()
            .range( [ 0, width]),

          scale_y = d3.scale.linear()
            .domain( [ 0, d3.max( data_extent_y)]).nice()
            .range( [ height, 0]);

      var container = d3.select( "#chart"),
          canvas = container.select( "svg"),
          vis = undefined,
          rules = undefined;

      // Construction des éléments de base à l'intérieur du DIV#chart,
      // dont le contenu effectif sera défini par la suite:
      //
      //   <svg width=... height=...>
      //     <g class=graph transform=translate(...)>
      //       <g class=rules> ...
      //       <path class=area d=... />
      //       <path class=line d=... />
      //     <text class=title> ...
      //
      if( canvas[0][0] == null) {
        // Canevas SVG
        canvas = container.append( "svg:svg")
            .attr( "width", width + m.left + m.right)
            .attr( "height", height + m.top + m.bottom);
        // Groupe pour positionner le graphe
        var graph = canvas.append( "svg:g")
            .attr( "class", "graph")
            .attr( "transform", "translate(" + m.left + "," + m.top + ")");
        // Groupe pour les lignes-guide
        rules = graph.append( "svg:g")
            .attr( "class", "rules");
        // Eléments pour la surface et la ligne du graphe
        graph.append( "svg:path")
          .attr( "class", "area");
        graph.append( "svg:path")
          .attr( "class", "line");
        // Elément texte avec titre du graphe
        canvas.append( "svg:text")
          .attr( "class", "title")
          .attr( "x", ( width + m.left + m.right) / 2)
          .attr( "y", height + m.top)
          .attr( "dy", "2.84em")
          .attr( "text-anchor", "middle");
      }

      // Mappe les données du graphe sur les descendants de l'élément
      // <g class=graph> (c-à-d. <path class=area> et <path class=line>)
      var vis = canvas.selectAll( "g.graph")
            .data( [ data]);

      var rules = vis.select( "g.rules"),
          rules_minmax = rules.select("g.rule.min-max");

      // Définition du titre du graphe
      canvas.select( "text.title").text( title);

      // (Re-)tracé de la grille: lignes-guide des abscisses X
      var ticks_x = scale_x.ticks( TICK_COUNT),
          tick_formatter_x = scale_x.tickFormat( TICK_COUNT),
          rules_x = rules.selectAll( "g.rule.x")
            .data( ticks_x);

      rules_x.enter()
          .append( "svg:g")
            .attr( "class", "rule x")
          .each( function() {
            var svg_g = d3.select( this);
            svg_g.append( "svg:line")
              .attr( "y1", 0)
              .attr( "y2", height - 1);
            svg_g.append( "svg:text")
              .attr( "y", height + 6)
              .attr( "dy", ".71em")
              .attr( "text-anchor", "middle");
          });

      rules_x.exit()
          .remove();

      rules_x.each( function( d) {
        var g_rule = d3.select( this);
        g_rule.select( "line")
          .attr( "x1", scale_x( d))
          .attr( "x2", scale_x( d));
        g_rule.select( "text")
          .attr( "x", scale_x( d))
          .text( tick_formatter_x( d));
      });

      // (Re-)tracé de la grille: lignes-guide des ordonnées Y
      var ticks_y = scale_y.ticks( TICK_COUNT),

          tick_formatter_y = scale_y.tickFormat( TICK_COUNT),

          rules_y = rules.selectAll( "g.rule.y")
            .data( ticks_y);

      rules_y.enter()
          .append( "svg:g")
            .attr( "class", "rule y")
          .each( function() {
            var g_rule = d3.select( this);
            g_rule.append( "svg:line")
              .attr( "class", function( d) { return d ? null : "axis"; })
              .attr( "x1", 0)
              .attr( "x2", width + 1);
            g_rule.append( "svg:text")
              .attr( "x", -6)
              .attr( "dy", ".35em")
              .attr( "text-anchor", "end");
          });

      rules_y.exit()
          .remove();

      rules_y.each( function( d) {
        var g_rule = d3.select( this);
        g_rule.select( "line")
          .attr( "y1", scale_y( d))
          .attr( "y2", scale_y( d));
        g_rule.select( "text")
          .attr( "y", scale_y( d))
          .text( tick_formatter_y( d));
      });

      // Tracé des lignes min / max
      var rules_minmax = rules.select( "g.rule.min-max");
      if( rules_minmax[0][0] == null)
        rules_minmax = rules.append( "svg:g")
          .attr( "class", "rule min-max");
      rules_minmax.selectAll( "line")
          .data( data_extent_y)
          .attr( "y1", scale_y)
          .attr( "y2", scale_y)
        .enter().append( "svg:line")
          .attr( "class", "min-max")
          .attr( "x1", 0)
          .attr( "y1", scale_y)
          .attr( "x2", width)
          .attr( "y2", scale_y);

      rules_minmax.selectAll( "text")
          .data( data_extent_y)
          .attr( "y", scale_y)
          .text( tick_formatter_y)
        .enter().append( "svg:text")
          .attr( "class", "min-max")
          .attr( "y", scale_y)
          .attr( "x", width + 6)
          .attr( "dy", ".35em")
          .attr( "text-anchor", "start")
          .text( tick_formatter_y);

      // Tracé du graphe (se souvenir que le tableau des données
      // a été "mappé" plus haut sur les deux éléments <path>)
      var coord_x = function( d) { return scale_x( attr_x( d)); },
          coord_y = function( d) { return scale_y( attr_y( d)); };

      vis.select( "path.area")
          .attr( "d", d3.svg.area()
            .x(  coord_x)
            .y0( height - 1)
            .y1( coord_y)
          );

      vis.select( "path.line")
          .attr( "d", d3.svg.line()
            .x( coord_x)
            .y( coord_y)
          );
    }
    </script>
    <style type="text/css">
      body {
        font-family: Arial, Helvetica Neue, Helvetica, sans-serif; }
      #chart {
        width: 960px; height: 480px;
        border: 1px solid #eee;
        font-size: 10px; }
      #chart .bar { fill: steelblue; }
      #chart .rule line { stroke: #eee; shape-rendering: crispEdges; }
      #chart .rule line.axis { stroke: black; }
      #chart .rule line.min-max { stroke: lightsteelblue; stroke-dasharray: 4,4; }
      #chart .rule text.min-max { fill: lightsteelblue; font-weight: bold; }
      #chart .area { fill: lightsteelblue; fill-opacity: .75; }
      #chart .line { fill: none; stroke: steelblue; stroke-width: 1.5px; }
      #chart text.title { fill: lightsteelblue; font-weight: bold; }
    </style>
  </head>
  <body>
    <div id="chart"></div>
    <script type="text/javascript">

      var data =
          %{graph_data};

      var // Value X accessor "location" (Slice location [mm], converted to [cm])
          attr_loc  = function( d) { return d.sl / 10; },

          // Value Y accessor "exposure" (X-ray tube current * Exposure time [mAs])
          attr_exp = function( d) { return d.xr * d.et / 1000; },

          width = 890,  // 890 + 35 (left) + 35 (right) = 960px (CSS width)
          height = 415, // 415 + 25 (top) + 40 (bottom) = 480px (CSS height)
          margins = { top: 25, right: 35, bottom: 40, left: 35 },

          title = "%{graph_title}";

      draw_area_graph( title, data, attr_loc, attr_exp, width, height, margins);

    </script>
  </body>
</html>
EOF
