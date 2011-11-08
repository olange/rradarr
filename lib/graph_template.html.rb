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

      var scale_x = d3.scale.ordinal().domain( d3.range( data.length))
            .rangeBands( [ 0, width - m.right - m.left], 0.05),

          scale_y = d3.scale.linear().domain( [ 0, d3.max( data, attr_y) ] )
            .range( [ 0, height - m.top - m.bottom]);

      var vis = d3.select("#chart")
        .append("svg:svg")
          .attr("width", width)
          .attr("height", height)
        .append("svg:g")
          .attr("transform", "translate(" + m.left + "," + m.top + ")");

      vis.selectAll("rect.bar")
          .data( data)
        .enter().append("svg:rect")
          .attr( "class", "bar")
          .attr( "x", function( d, i) { return scale_x( i); })
          .attr( "y", function( d)    { return height - m.top - m.bottom - scale_y( attr_y( d)); })
          .attr( "width", scale_x.rangeBand())
          .attr( "height", function( d) {
            return scale_y( attr_y( d)); });

      vis.selectAll("text.value")
          .data( data)
        .enter().append("svg:text")
          .attr( "class", "value")
          .attr( "x", function( d, i) { return scale_x( i) + scale_x.rangeBand() / 2; })
          .attr( "y", function( d)    { return height - m.top - m.bottom - scale_y( attr_y( d)); })
          .attr( "dy", -2)
          .attr( "text-anchor", "middle")
          .text( attr_y);

      vis.selectAll("text.label")
          .data( data)
        .enter().append("svg:text")
          .attr( "class", "label")
          .attr( "x", function( d, i) { return scale_x( i) + scale_x.rangeBand() / 2; })
          .attr( "y", height - m.top - m.bottom - scale_y( 0))
          .attr( "dy", 12)
          .attr( "text-anchor", "middle")
          .text( attr_x);

      vis.append("svg:line")
        .attr("class", "xaxis")
        .attr("x1", 0)
        .attr("x2", width - m.right - m.left)
        .attr("y1", height - m.top - m.bottom - scale_y( 0))
        .attr("y2", height - m.top - m.bottom - scale_y( 0));
    }
    </script>
    <style type="text/css">
      #chart {
        width: 960px;
        height: 480px;
        border: 1px solid lightgray;
        font-family: Arial, Helvetica, sans-serif;
        font-size: 12px;
      }
      #chart .bar {
        fill: steelblue;
      }
      #chart .xaxis {
        stroke: black;
      }
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

          width = 960,
          height = 480,
          margins = { top: 20, right: 10, bottom: 20, left: 10 };

      draw_area_graph( data, attr_loc, attr_xray, width, height, margins);

    </script>
  </body>
</html>
EOF

