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
def html_graph_for( data)
  return BARGRAPH_TEMPLATE % { :graph_data => data.to_json }
end

# Modèle de document HTML avec script D3.js pour tracer histogramme.
# Contient un marqueur %{graph_data}, qui doit être remplacé par les
# valeurs effectives (cf. html_graph_for).
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
    // data: tableau de tuples (X,Y)
    //   par exemple: [ { loc: 66.125, xray: 140.0 }, ... ]
    //
    // attr_x: accesseur permettant de lire la valeur X d'un tuple
    //   par exemple: function(d) { return d.loc; }
    //
    // attr_y: accesseur permettant de lire la valeur Y d'un tuple
    //   par exemple: function(d) { return d.xray; }
    //
    // width: largeur du graphe, en pixels; par exemple: 960.
    //
    // height: hauteur du graphe, en pixels; par exemple: 480.
    //
    // m: marges intérieures du graphe; il doit s'agir d'un objet,
    //   qui doit posséder les attributs top, bottom, left et right;
    //   par exemple: { top: 10, right: 5, bottom: 10, left: 5 }
    function draw_area_graph( data, attr_x, attr_y, width, height, m) {
      var TICK_COUNT = 10;

      var scale_x = d3.scale.linear()
            .domain( d3.extent( data, attr_x)).nice()
            .range( [ 0, width]),

          scale_y = d3.scale.linear()
            .domain( [ 0, d3.max( data, attr_y)]).nice()
            .range( [ height, 0]);

      var vis = d3.select( "#chart")
        .append( "svg:svg")
          .data( [ data])   // astuce: le tableau imbriqué 'data' sera mappé sur élément descendant
          .attr( "width", width + m.left + m.right)
          .attr( "height", height + m.top + m.bottom)
        .append( "svg:g")
          .attr( "transform", "translate(" + m.left + "," + m.top + ")");

      // Tracé de la grille
      var rules_x = vis.selectAll( "g.rule")
          .data( scale_x.ticks( TICK_COUNT))
        .enter().append( "svg:g")
          .attr( "class", "rule");

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

      // Tracé du graphe
      var coord_x = function( d) { return scale_x( attr_x( d)); },
          coord_y = function( d) { return scale_y( attr_y( d)); };

      // FIXME: pourquoi le dernier fill/trait revient-il au début?
      vis.append( "svg:path")
          .attr( "class", "area")
          .attr( "d", d3.svg.area()
            .x(  coord_x)
            .y0( height - 1)
            .y1( coord_y)
          );

      // FIXME: itou, pourquoi le dernier trait revient-il au début?
      vis.append( "svg:path")
          .attr( "class", "line")
          .attr( "d", d3.svg.line()
            .x( coord_x)
            .y( coord_y)
          );

      vis.selectAll( "circle.area")
          .data( data)
        .enter().append( "svg:circle")
          .attr( "class", "area")
          .attr( "cx", coord_x)
          .attr( "cy", coord_y)
          .attr( "r", 3.0);
    }
    </script>
    <style type="text/css">
      body {
        font-family: Arial, Helvetica, sans-serif; }
      #chart {
        width: 960px; height: 450px;
        border: 1px solid #eee;
        font-size: 10px; }
      #chart .bar { fill: steelblue; }
      #chart .xaxis { stroke: black; }
      #chart .rule line {
        stroke: #eee; shape-rendering: crispEdges; }
      #chart .rule line.axis { stroke: black; }
      #chart .area { fill: lightsteelblue; fill-opacity: .75; }
      #chart .line, #chart circle.area {
        fill: none; stroke: steelblue; stroke-width: 1.5px; }
      #chart circle.area { fill: white; }
    </style>
  </head>
  <body>
    <div id="chart"></div>
    <script type="text/javascript">

      var data =
          %{graph_data}
          ,

          attr_loc  = function( d) { return d.l; },   // Slice location accessor
          attr_xray = function( d) { return d.x; },   // X-ray tube current accessor

          width = 900,  // 900 + 35 (left) + 25 (right) = 960px (CSS width)
          height = 400, // 400 + 25 (top) + 25 (bottom) = 450px (CSS height)
          margins = { top: 25, right: 25, bottom: 25, left: 35 };

      draw_area_graph( data, attr_loc, attr_xray, width, height, margins);

    </script>
  </body>
</html>
EOF
