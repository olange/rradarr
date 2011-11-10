#! /usr/bin/env ruby
# -*- encoding: utf-8 -*-

# Author:: Olivier Lange (mailto:olange@petit-atelier.ch)
# Copyright:: (c) 2011 Tristan Zand & Olivier Lange
# License:: GNU GPL, either v3 or (at your option) any later version.

require 'json/ext'

# Retourne un document HTML permettant de tracer un histogramme à partir
# d'un ensemble de coordonnées <Slice location, X-ray tube current>.
#
# Le jeu de données doit être communiqué sous forme d'un tableau
# de coordonnées, où chaque coordonnée doit être un hash de la
# forme { :l => FLOAT, :x => FLOAT }. Par exemple:
#
# [ { :l => 66.125, :x => 140.0 }, { :l => 66.750, :x => 145.5 }, ... ]
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
    // rectilignes <X,Y> (X: abscisse/libellé et Y: ordonnée/valeur
    // de l'un des points du graphe).
    //
    // title: titre du graphe, qui sera inscrit sous l'axe X.
    //
    // data: tableau de tuples (X,Y)
    //   par exemple: [ { loc: 66.125, xray: 140.0 }, ... ]
    //
    // attr_x: accesseur permettant de lire la valeur X d'un tuple
    //   par exemple: function(d) { return d.loc; }
    //
    // attr_y: accesseur permettant de lire la valeur Y d'un tuple
    //   par exemple: function(d) { return d.xray; }
    //
    // width: largeur intérieure du graphe, en pixels; par exemple: 960.
    //
    // height: hauteur intérieure du graphe, en pixels; par exemple: 480.
    //
    // m: marges du graphe; il doit s'agir d'un objet, qui doit posséder
    //   les attributs top, bottom, left et right; par exemple:
    //   { top: 10, right: 5, bottom: 10, left: 5 }
    //
    // Noter que la largeur totale du graphe sera width + m.left + m.right
    // et que sa hauteur sera height + m.top + m.bottom.
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

      var canvas = d3.select( "#chart")
          .data( [ data])
        .append( "svg:svg")
          .attr( "width", width + m.left + m.right)
          .attr( "height", height + m.top + m.bottom),
          // astuce: le tableau imbriqué 'data' sera mappé sur nouvel
          // élément descendant svg:g créé ci-après

          vis = canvas.append( "svg:g")
          .attr( "transform", "translate(" + m.left + "," + m.top + ")");

      // Titre du graphe
      if( title != "") {
        canvas.append( "svg:text")
          .attr( "class", "title")
          .attr( "x", ( width + m.left + m.right) / 2)
          .attr( "y", height + m.top)
          .attr( "dy", "2.84em")
          .attr( "text-anchor", "middle")
          .text( title);
      }

      // Tracé de la grille
      var rules_x = vis.selectAll( "g.rule")
          .data( scale_x.ticks( TICK_COUNT))
        .enter().append( "svg:g")
          .attr( "class", "rule xy");

      rules_x.append( "svg:line")
          .attr( "x1", scale_x)
          .attr( "x2", scale_x)
          .attr( "y1", 0)
          .attr( "y2", height - 1);

      rules_x.append( "svg:text")
          .attr( "x", scale_x)
          .attr( "y", height + 6)
          .attr( "dy", ".71em")
          .attr( "text-anchor", "middle")
          .text( scale_x.tickFormat( TICK_COUNT));

      var rules_y = vis.selectAll( "g.rule")
          .data( scale_y.ticks( TICK_COUNT))
        .enter().append( "svg:g")
          .attr( "class", "rule y");

      var rules_y = vis.selectAll( "g.rule")
          .data( scale_y.ticks( TICK_COUNT));

      rules_y.append( "svg:line")
          .attr( "class", function( d) { return d ? null : "axis"; })
          .attr( "y1", scale_y)
          .attr( "y2", scale_y)
          .attr( "x1", 0)
          .attr( "x2", width + 1);

      rules_y.append( "svg:text")
          .attr( "y", scale_y)
          .attr( "x", -6)
          .attr( "dy", ".35em")
          .attr( "text-anchor", "end")
          .text( scale_y.tickFormat( TICK_COUNT));

      // Tracé des lignes min / max
      var rules_minmax = vis.append( "svg:g")
          .attr( "class", "rule min-max");

      rules_minmax.selectAll( "line")
          .data( data_extent_y)
        .enter().append( "svg:line")
          .attr( "class", "min-max")
          .attr( "x1", 0)
          .attr( "y1", scale_y)
          .attr( "x2", width)
          .attr( "y2", scale_y);

      rules_minmax.selectAll( "text")
          .data( data_extent_y)
        .enter().append( "svg:text")
          .attr( "class", "min-max")
          .attr( "y", scale_y)
          .attr( "x", width + 6)
          .attr( "dy", ".35em")
          .attr( "text-anchor", "start")
          .text( scale_y.tickFormat( TICK_COUNT));

      // Tracé du graphe
      var coord_x = function( d) { return scale_x( attr_x( d)); },
          coord_y = function( d) { return scale_y( attr_y( d)); };

      vis.append( "svg:path")
          .attr( "class", "area")
          .attr( "d", d3.svg.area()
            .x(  coord_x)
            .y0( height - 1)
            .y1( coord_y)
          );

      vis.append( "svg:path")
          .attr( "class", "line")
          .attr( "d", d3.svg.line()
            .x( coord_x)
            .y( coord_y)
          );
    }
    </script>
    <style type="text/css">
      body {
        font-family: Arial, Helvetica, sans-serif; }
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

      var attr_loc  = function( d) { return d.l; },   // Slice location accessor
          attr_xray = function( d) { return d.x; },   // X-ray tube current accessor

          width = 890,  // 890 + 35 (left) + 35 (right) = 960px (CSS width)
          height = 415, // 415 + 25 (top) + 40 (bottom) = 480px (CSS height)
          margins = { top: 25, right: 35, bottom: 40, left: 35 },

          title = "%{graph_title}";

      draw_area_graph( title, data, attr_loc, attr_xray, width, height, margins);

    </script>
  </body>
</html>
EOF
