CREATE TABLE Rain_gauge
(
  id_gauge integer PRIMARY KEY,
  name character varying(50),
  num_station integer,
  location geometry
);

CREATE TABLE Precipitation
(
  gauge integer,
  date date,
  time time,
  accumulated double precision,
  PRIMARY KEY (gauge, date, time),
  FOREIGN KEY (gauge) REFERENCES Rain_gauge(id_gauge)
	ON DELETE NO ACTION
	ON UPDATE CASCADE
);

CREATE TABLE Region
(
  id_region integer PRIMARY KEY,
  name character varying(50),
  boundary geometry
);

CREATE TABLE District
(
  id_district integer PRIMARY KEY,
  region integer,
  name character varying(50),
  boundary geometry,
  FOREIGN KEY (region) REFERENCES Region(id_region)
	ON DELETE RESTRICT
	ON UPDATE CASCADE
);


