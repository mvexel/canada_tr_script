#!/bin/sh

OSMOSISDIR="/usr/local/Cellar/osmosis/0.45/libexec/"
METROSHAPE="gcma000b11a_e/gcma000b11a_e.shp"
DBNAME="osm"
DATE=`date +%Y%m%d`

# Create OSM database

createdb $DBNAME
psql -d $DBNAME -c 'create extension hstore'
psql -d $DBNAME -c 'create extension postgis'
psql -d $DBNAME -f $OSMOSISDIR/script/pgsnapshot_schema_0.6.sql
psql -d $DBNAME -f $OSMOSISDIR/script/pgsnapshot_schema_0.6_linestring.sql

# Load Canada metros

shp2pgsql -i -I -d -W LATIN1 $METROSHAPE > canada-metro.sql
psql -d $DBNAME -f canada-metro.sql

# Get Canada TR as OSM XML

curl "https://overpass-api.de/api/interpreter?data=%5Bout%3Axml%5D%3B%0Aarea%5Bname%3DCanada%5D-%3E.c%3B%0Arelation%5Btype%3Drestriction%5D%28area.c%29%3B%0A%28._%3B%3E%3B%29%3B%0Aout%20meta%3B" > canada_relations.osm.xml

# Load into OSM database

osmosis --rx canada_relations.osm.xml --wp database=osm 

# Create proxy geometries for unique turn restrictions

psql -d $DBNAME -c "create table fromways as (select w.linestring, w.id way_id, r.relation_id relation_id from ways w, relation_members r where w.id = r.member_id and r.member_type = 'W' and r.member_role = 'from');"

# Run query

psql -d canada -c "\copy (select count(w.way_id) cnt, m.cmaname from fromways w, gcma000b11a_e m where w.linestring && m.geom group by m.cmaname order by cnt desc) to 'out/canada-tr-$DATE.csv' with csv"

# Clean up

dropdb $DBNAME
rm canada-metro.sql canada_relations.osm.xml