-------------------------------------------
-- creazione del tipo di dato power_RMS  --
-------------------------------------------

CREATE TYPE power_RMS AS(

	power double precision,
	RMS double precision
);

-------------------------------------------
-- creazione del tipo di dato cutoff_RMS --
-------------------------------------------

CREATE TYPE cutoff_RMS AS(

	cutoff double precision,
	RMS double precision
);

-------------------------------------------------------------------------------------------------------------------
-- 	funzione che date le dimensioni e le coordinate x e y di un quadrato calcola la griglia per l'interpolazione --
-------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_14(xmin double precision, xmax double precision, ymin double precision, ymax double precision, nx integer, ny integer)
  RETURNS SETOF record AS
$BODY$

	library(gstat)
	ngridx<-nx
	ngridy<-ny
	xgrid<-seq(xmin, xmax, length=ngridx)
	ygrid<-seq(ymin, ymax, length=ngridy)
	grid <- list(x=xgrid,y=ygrid)
	grid$xr <- range(grid$x)
	grid$xs <- grid$xr[2] - grid$xr[1]
	grid$yr <- range(grid$y)
	grid$ys <- grid$yr[2] - grid$yr[1]
	grid$xy <- data.frame(cbind(c(matrix(grid$x, length(grid$x), length(grid$y))), c(matrix(grid$y, length(grid$x), length(grid$y), byrow=T))))
	return(grid$xy)

$BODY$
  LANGUAGE plr;

-------------------------------------------------------------------------------
-- 	funzione che filtra i punti di una griglia contenuti in una data regione --
-------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_15(region_name text, x double precision[], y double precision[])
  RETURNS SETOF record AS
$BODY$
DECLARE 
	point geometry[];
	c integer;
	i double precision;
	p geometry;
	is_in boolean;
	rec record;
BEGIN
	
	c = 1;
	FOREACH i IN array x
	LOOP
		point[c] = ST_SetSRID(ST_MakePoint(i,y[c]),4326);
		c = c + 1;
	END LOOP;

	FOREACH p IN array point
	LOOP
		SELECT ST_Contains(r.boundary, p) AS is_in, ST_X(p), ST_Y(p)
		FROM region AS r
		WHERE r.name = region_name
		INTO rec;

		IF rec.is_in THEN
			RETURN NEXT rec;
		END IF;
	END LOOP;

END 
$BODY$
  LANGUAGE plpgsql;

--------------------------------------------------------
-- 	funzione che esegue l'idw dati i dovuti parametri --
--------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_16(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], xg double precision[], yg double precision[], accumulated double precision[], power double precision, path text)
  RETURNS integer AS
$BODY$

	library(gstat);
	library(raster);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);
	dfg <- data.frame(f = xg, g = yg)

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);
	grid <- SpatialPixelsDataFrame(points = dfg[c("f", "g")], data = dfg)

	idw.out <- idw(c ~ 1, spdf, grid, idp = power)

	idw.asc <- raster(idw.out)

	writeRaster(idw.asc, filename = path, overwrite=TRUE)
	
	return(nrow(grid))

$BODY$
  LANGUAGE plr;

-------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che data una data, un'intervallo di tempo, la potenza dell'interpolazione e le dimensioni della griglia esegue l'idw  --
-------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION idw_withinHours(region_name text, day text, from_h text, to_h text, path text, power double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day,from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_16(id_gau, gauge_na, x, y, xgf, ygf, acc, power, path);
	
END;
$BODY$
  LANGUAGE plpgsql;

-------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date, la potenza dell'interpolazione e le dimensioni della griglia esegue l'idw --
-------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION idw_withinDays(region_name text, from_d text, to_d text, path text, power double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_16(id_gau, gauge_na, x, y, xgf, ygf, acc, power, path);
	
END;
$BODY$
  LANGUAGE plpgsql;


----------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di potenze calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
----------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_17(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], accumulated double precision[], from_p double precision, to_p double precision, by_p double precision)
  RETURNS SETOF record AS
$BODY$

	library(gstat);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);

	do_cv = function(idp) {
  		idw_cv <- gstat(id = "cv", formula = c ~ 1, data = spdf, set = list(idp = idp))
		idw.out = gstat.cv(idw_cv)
		return(sqrt(mean(idw.out$residual^2)))
	}

	idw_pow = seq(from_p, to_p, by = by_p)

	cv = sapply(idw_pow, do_cv);

	return (data.frame(idp = idw_pow, cv_rmse = cv))
	
$BODY$
  LANGUAGE plr;


---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che data una data, un'intervallo di ore e un intervallo di potenze calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
---------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION idw_crossValidation_withinHours(day text, from_h text, to_h text, from_p double precision, to_p double precision, by_p double precision)
  RETURNS SETOF power_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	ret power_RMS;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day, from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_17(id_gau, gauge_na, x, y, acc, from_p, to_p, by_p) t(idp double precision, val double precision)
	LOOP	
			ret.power = row1.idp;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;

 
----------------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date e un intervallo di potenze calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
----------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION idw_crossValidation_withinDays(from_d text, to_d text, from_p double precision, to_p double precision, by_p double precision)
  RETURNS SETOF power_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	ret power_RMS;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_17(id_gau, gauge_na, x, y, acc, from_p, to_p, by_p) t(idp double precision, val double precision)
	LOOP
			ret.power = row1.idp;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;


-------------------------------------------------------------
-- 	funzione che esegue il kriging dati i dovuti parametri --
-------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_18(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], xg double precision[], yg double precision[], accumulated double precision[], cut double precision, path text)
  RETURNS integer AS
$BODY$

	library(gstat);
	library(raster);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);
	dfg <- data.frame(f = xg, g = yg)

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);
	grid <- SpatialPixelsDataFrame(points = dfg[c("f", "g")], data = dfg)

	vgm <- variogram(c~1, spdf, cutoff = cut)

	dist <- max(vgm$dist)*70/100;
	psill <- max(vgm$gamma)
	fit = fit.variogram(vgm, model = vgm(psill, "Sph", dist))

	kriged = krige(c~1, spdf, grid, model = fit)

	kriged.asc <- raster(kriged)

	writeRaster(kriged.asc, filename = path, overwrite=TRUE)
	
	return(nrow(grid))

$BODY$
  LANGUAGE plr;

  -------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che data una data, un'intervallo di tempo, il cutoff dell'interpolazione e le dimensioni della griglia esegue il kriging  --
-------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION kriging_withinHours(region_name text, day text, from_h text, to_h text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day,from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_18(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date, una lag distance e le dimensioni della griglia esegue il kriging --
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION kriging_withinDays(region_name text, from_d text, to_d text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_18(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;


---------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di cutoff calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
---------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_19(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], accumulated double precision[], from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF record AS
$BODY$

	library(gstat);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);

	do_cv = function(cut) {
  		vgm <- variogram(c~1, spdf, cutoff = cut)
  		dist <- max(vgm$dist)*70/100;
		psill <- max(vgm$gamma)
		fit = fit.variogram(vgm, model = vgm(psill, "Sph", dist))
		out <- krige.cv(c~1, spdf, model = fit)
		return(sqrt(mean(out$residual^2)))
	}

	krige_cut = seq(from_c, to_c, by = by_c)

	cv = sapply(krige_cut, do_cv);

	return (data.frame(cut = krige_cut, cv_rmse = cv))
	
$BODY$
  LANGUAGE plr;

 ----------------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di ore e un intervallo di cutoff calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
----------------------------------------------------------------------------------------------------------------------------------------------------------

  
    CREATE OR REPLACE FUNCTION kriging_crossValidation_withinHours(day text, from_h text, to_h text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day,from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_19(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;
  
----------------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date e un intervallo di cutoff calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
----------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION kriging_crossValidation_withinDays(from_d text, to_d text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_19(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;


----------------------------------------------------------------------------------------------
-- 	funzione che esegue il kriging ponendo a zero i valori negativi dati i dovuti parametri --
----------------------------------------------------------------------------------------------


CREATE OR REPLACE FUNCTION UDF_21(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], xg double precision[], yg double precision[], accumulated double precision[], cut double precision, path text)
  RETURNS integer AS
$BODY$

	library(gstat);
	library(raster);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);
	dfg <- data.frame(f = xg, g = yg)

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);
	grid <- SpatialPixelsDataFrame(points = dfg[c("f", "g")], data = dfg)

	vgm <- variogram(c~1, spdf, cutoff = cut)

	dist <- max(vgm$dist)*70/100;
	psill <- max(vgm$gamma)
	fit = fit.variogram(vgm, model = vgm(psill, "Sph", dist))

	kriged = krige(c~1, spdf, grid, model = fit)

	df <- as.data.frame(kriged)
	df$var1.pred[df$var1.pred < 0] <- 0
	kriged.zero <- SpatialPixelsDataFrame(points = df[1:2], data = df[3:4])

	kriged.asc <- raster(kriged.zero)

	writeRaster(kriged.asc, filename = path, overwrite=TRUE)
	
	return(nrow(grid))

$BODY$
  LANGUAGE plr;

--------------------------------------------------------------------------------------------
-- 	funzione che esegue il kriging ponendo a na i valori negativi dati i dovuti parametri --
--------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION UDF_20(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], xg double precision[], yg double precision[], accumulated double precision[], cut double precision, path text)
  RETURNS integer AS
$BODY$

	library(gstat);
	library(raster);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);
	dfg <- data.frame(f = xg, g = yg)

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);
	grid <- SpatialPixelsDataFrame(points = dfg[c("f", "g")], data = dfg)

	vgm <- variogram(c~1, spdf, cutoff = cut)

	dist <- max(vgm$dist)*70/100;
	psill <- max(vgm$gamma)
	fit = fit.variogram(vgm, model = vgm(psill, "Sph", dist))

	kriged = krige(c~1, spdf, grid, model = fit)

	df <- as.data.frame(kriged)
	df$var1.pred[df$var1.pred < 0] <- NA
	kriged.zero <- SpatialPixelsDataFrame(points = df[1:2], data = df[3:4])

	kriged.asc <- raster(kriged.zero)

	writeRaster(kriged.asc, filename = path, overwrite=TRUE)
	
	return(nrow(grid))

$BODY$
  LANGUAGE plr;

  ------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di ore, una lag distance e le dimensioni della griglia esegue il kriging ponendo a na i valori negativi  --
------------------------------------------------------------------------------------------------------------------------------------------------

  
  CREATE OR REPLACE FUNCTION NaKriging_withinHours(region_name text, day text, from_h text, to_h text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day,from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_20(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date, una lag distance e le dimensioni della griglia esegue il kriging ponendo a na i valori negativi  --
------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION NaKriging_withinDays(region_name text, from_d text, to_d text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_20(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;

  --------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di ore, una lag distance e le dimensioni della griglia esegue il kriging ponendo a zero i valori negativi  --
--------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION zeroKriging_withinHours(region_name text, day text, from_h text, to_h text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day,from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_21(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
--------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date, una lag distance e le dimensioni della griglia esegue il kriging ponendo a zero i valori negativi  --
--------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION zeroKriging_withinDays(region_name text, from_d text, to_d text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_21(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;


----------------------------------------------------------------------------------------------------------------
-- 	funzione che esegue il kriging eseguendo una trasformazione logaritmica del campo dati i dovuti parametri --
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_22(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], xg double precision[], yg double precision[], accumulated double precision[], cut double precision, path text)
  RETURNS integer AS
$BODY$

	library(gstat);
	library(raster);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);
	dfg <- data.frame(f = xg, g = yg)

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);
	grid <- SpatialPixelsDataFrame(points = dfg[c("f", "g")], data = dfg)

	vgm <- variogram(c~1, spdf, cutoff = cut)
	
	dist <- max(vgm$dist)*70/100
	psill <- max(vgm$gamma)
	fit = fit.variogram(vgm, model = vgm(psill, "Sph", dist))

	kriged = krige(log(c+1) ~ 1, spdf, grid, model = fit)
	df.log <- as.data.frame(kriged)
	df.log$var1.pred <- exp(df.log$var1.pred) - 1
	kriged.log <- SpatialPixelsDataFrame(points = df.log[1:2], data = df.log[3:4])

	kriged.asc <- raster(kriged.log)

	writeRaster(kriged.asc, filename = path, overwrite=TRUE)
	
	return(nrow(grid))

$BODY$
  LANGUAGE plr;
  
  --------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di ore, una lag distance e le dimensioni della griglia esegue il kriging  eseguendo una trasformazione logaritmica del campo --
--------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION logarithmickriging_withinhours(region_name text, day text, from_h text, to_h text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day,from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_22(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date, una lag distance e le dimensioni della griglia esegue il kriging  eseguendo una trasformazione logaritmica del campo --
--------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION logarithmicKriging_withinDays(region_name text, from_d text, to_d text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_22(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di cutoff calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
---------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_23(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], accumulated double precision[], from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF record AS
$BODY$

	library(gstat);

	df <- data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);

	do_cv = function(cut) {
  		vgm <- variogram(c~1, spdf, cutoff = cut)
  		dist <- max(vgm$dist)*70/100
		psill <- max(vgm$gamma)
		fit = fit.variogram(vgm, model = vgm(psill, "Sph", dist))
		out <- krige.cv(log(c+1)~1, spdf, model = fit)
		return(sqrt(mean((exp(out$residual)-1)^2)))
	}

	krige_cut = seq(from_c, to_c, by = by_c)

	cv = sapply(krige_cut, do_cv);

	return (data.frame(cut = krige_cut, cv_rmse = cv))
	
$BODY$
  LANGUAGE plr;
  
  CREATE OR REPLACE FUNCTION logarithmicKriging_crossValidation_withinHours(day text, from_h text, to_h text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day,from_h,to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_23(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------------------------------------------------
-- 	funzione che dato un intervallo di date e un intervallo di cutoff calcola l'errore quadratico medio relativo ad ogni valore definito in precedenza --
----------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION logarithmicKriging_crossValidation_withinDays(from_d text, to_d text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_23(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;



----------------------------
-- Funzioni in appendice  --
----------------------------

----------------------------------------------------------------------------------------------------------------------------------------------------------
-- 									Simple IDW																													--
----------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION simpleIdw(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], accumulated double precision[], nx integer, ny integer, power double precision, path text)
  RETURNS integer AS
$BODY$

	library(gstat);
	library(raster);

	df <-data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);

	ngridx<-nx
	ngridy<-ny
	xgrid<-seq(min(coordinates(spdf)[,1]),max(coordinates(spdf)[,1]),length=ngridx)
	ygrid<-seq(min(coordinates(spdf)[,2]),max(coordinates(spdf)[,2]),length=ngridy)
	grid <- list(x=xgrid,y=ygrid)
	grid$xr <- range(grid$x)
	grid$xs <- grid$xr[2] - grid$xr[1]
	grid$yr <- range(grid$y)
	grid$ys <- grid$yr[2] - grid$yr[1]
	grid$xy <- data.frame(cbind(c(matrix(grid$x, length(grid$x), length(grid$y))), c(matrix(grid$y, length(grid$x), length(grid$y), byrow=T))))
	
	grid <- SpatialPixelsDataFrame(points = grid$xy[c("X1", "X2")], data = grid$xy)

	idw.out <- idw(c ~ 1, spdf, grid, idp = power)

	idw.asc <- raster(idw.out)

	writeRaster(idw.asc, filename = path, overwrite=TRUE)
	
	return(nrow(grid))

$BODY$
  LANGUAGE plr;

    CREATE OR REPLACE FUNCTION simpleIdw_withinHours(day text, from_h text, to_h text, path text, power double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	row record;
	id_gau integer[];
	gauge_na character varying(50)[];
	x double precision[];
	y double precision[];
	acc double precision[];
	i integer;
BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day, from_h, to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	RETURN simpleIdw(id_gau, gauge_na, x, y, acc, nx, ny, power, path);
END;
$BODY$
  LANGUAGE plpgsql;

  CREATE OR REPLACE FUNCTION simpleIdw_withinDays(from_d text, to_d text, path text, power double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	row record;
	id_gau integer[];
	gauge_na character varying(50)[];
	x double precision[];
	y double precision[];
	acc double precision[];
	i integer;
BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	RETURN simpleIdw(id_gau, gauge_na, x, y, acc, nx, ny, power, path);
END;
$BODY$
  LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------------------------------------------------
-- 									Simple kriging																													--
----------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION simpleKriging(id_gauge integer[], gauge_name character varying[], x double precision[], y double precision[], accumulated double precision[], nx integer, ny integer, cut double precision, path text)
  RETURNS integer AS
$BODY$

	library(gstat);
	library(raster);

	df <-data.frame(a = id_gauge, b = gauge_name, c = accumulated, d = x, e = y);

	spdf <- SpatialPointsDataFrame(df[4:5], df[1:3]);

	ngridx<-nx
	ngridy<-ny
	xgrid<-seq(min(coordinates(spdf)[,1]),max(coordinates(spdf)[,1]),length=ngridx)
	ygrid<-seq(min(coordinates(spdf)[,2]),max(coordinates(spdf)[,2]),length=ngridy)
	grid <- list(x=xgrid,y=ygrid)
	grid$xr <- range(grid$x)
	grid$xs <- grid$xr[2] - grid$xr[1]
	grid$yr <- range(grid$y)
	grid$ys <- grid$yr[2] - grid$yr[1]
	grid$xy <- data.frame(cbind(c(matrix(grid$x, length(grid$x), length(grid$y))), c(matrix(grid$y, length(grid$x), length(grid$y), byrow=T))))
	
	grid <- SpatialPixelsDataFrame(points = grid$xy[c("X1", "X2")], data = grid$xy)
	vgm <- variogram(c~1, spdf, cutoff = cut)
	
	dist <- max(vgm$dist)*70/100
	psill <- max(vgm$gamma)
	fit = fit.variogram(vgm, model = vgm(psill, "Sph", dist))

	kriged = krige(c~1, spdf, grid, model = fit)

	kriged.asc <- raster(kriged)

	writeRaster(kriged.asc, filename = path, overwrite=TRUE)
	
	return(nrow(grid))

$BODY$
  LANGUAGE plr;

 CREATE OR REPLACE FUNCTION simpleKriging_withinHours(day text, from_h text, to_h text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	row record;
	id_gau integer[];
	gauge_na character varying(50)[];
	x double precision[];
	y double precision[];
	acc double precision[];
	i integer;
BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_3(day, from_h, to_h)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	RETURN simpleKriging(id_gau, gauge_na, x, y, acc, nx, ny, cut, path);
END;
$BODY$
  LANGUAGE plpgsql; 

  CREATE OR REPLACE FUNCTION simpleKriging_withinDays(from_d text, to_d text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	row record;
	id_gau integer[];
	gauge_na character varying(50)[];
	x double precision[];
	y double precision[];
	acc double precision[];
	i integer;
BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_4(from_d,to_d)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	RETURN simpleKriging(id_gau, gauge_na, x, y, acc, nx, ny, cut, path);
END;
$BODY$
  LANGUAGE plpgsql;
  
  ----------------------------------------------------------------------------------------------------------------------------------------------------------
-- 										Months and Years																												--
----------------------------------------------------------------------------------------------------------------------------------------------------------
  
   CREATE OR REPLACE FUNCTION idw_withinMonths(region_name text, from_m text, to_m text, path text, power double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_16(id_gau, gauge_na, x, y, xgf, ygf, acc, power, path);
	
END;
$BODY$
  LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION idw_withinYears(region_name text, from_y text, to_y text, path text, power double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_16(id_gau, gauge_na, x, y, xgf, ygf, acc, power, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
CREATE OR REPLACE FUNCTION idw_crossValidation_withinMonths(from_m text, to_m text, from_p double precision, to_p double precision, by_p double precision)
  RETURNS SETOF power_rms AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 power_rms;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_17(id_gau, gauge_na, x, y, acc, from_p, to_p, by_p) t(idp double precision, val double precision)
	LOOP
			return next row1;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;

   CREATE OR REPLACE FUNCTION idw_crossValidation_withinYears(from_y text, to_y text, from_p double precision, to_p double precision, by_p double precision)
  RETURNS SETOF power_rms AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 power_rms;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_17(id_gau, gauge_na, x, y, acc, from_p, to_p, by_p) t(idp double precision, val double precision)
	LOOP
			return next row1;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION kriging_withinMonths(region_name text, from_m text, to_m text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_18(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION kriging_withinYears(region_name text, from_y text, to_y text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_18(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION logarithmicKriging_withinMonths(region_name text, from_m text, to_m text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_22(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION logarithmicKriging_withinYears(region_name text, from_y text, to_y text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_22(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION NaKriging_withinMonths(region_name text, from_m text, to_m text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_20(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
CREATE OR REPLACE FUNCTION NaKriging_withinYears(region_name text, from_y text, to_y text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_20(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;  
 
 CREATE OR REPLACE FUNCTION zeroKriging_withinMonths(region_name text, from_m text, to_m text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_21(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION zeroKriging_withinYears(region_name text, from_y text, to_y text, path text, cut double precision, nx integer, ny integer)
  RETURNS integer AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	row1 record;
	xg double precision[];
	yg double precision[];
	ig integer;

	row2 record;
	xgf double precision[];
	ygf double precision[];
	igf integer;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	ig = 0;
	FOR row1 IN SELECT *
		FROM UDF_14(11, 14.5, 40.5, 44, nx, ny) t(xgrid double precision, ygrid double precision)
	LOOP
		xg[ig] = row1.xgrid;
		yg[ig] = row1.ygrid;
		ig = ig + 1;
	END LOOP;

	

	igf = 0;
	FOR row2 IN SELECT *
		FROM UDF_15(region_name, xg, yg) t(is_in boolean, xgridfilter double precision, ygridfilter double precision)
	LOOP
		xgf[igf] = row2.xgridfilter;
		ygf[igf] = row2.ygridfilter;
		igf = igf + 1;
	END LOOP;

	return UDF_21(id_gau, gauge_na, x, y, xgf, ygf, acc, cut, path);
	
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION kriging_crossValidation_withinMonths(from_m text, to_m text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_19(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION kriging_crossValidation_withinYears(from_y text, to_y text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_19(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION logarithmicKriging_crossValidation_withinMonths(from_m text, to_m text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_26(from_m,to_m)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_23(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION logarithmicKriging_crossValidation_withinYears(from_y text, to_y text, from_c double precision, to_c double precision, by_c double precision)
  RETURNS SETOF cutoff_RMS AS
$BODY$
DECLARE
	id_gau integer[];
	gauge_na character varying(50)[];
	acc double precision[];

	row record;
	x double precision[];
	y double precision[];
	i integer;

	ret cutoff_RMS;
	row1 record;

BEGIN
	i = 0;
	FOR row IN SELECT id_gauge AS id, gauge_name AS name, sum AS a, ST_X(location) AS xx, ST_Y(location) AS yy
		FROM UDF_27(from_y,to_y)
	LOOP
		id_gau[i] = row.id;
		gauge_na[i] = row.name;
		x[i] = row.xx;
		y[i] = row.yy;
		acc[i] = row.a;
		i = i + 1;
	END LOOP;

	FOR row1 IN SELECT * 
		  FROM UDF_23(id_gau, gauge_na, x, y, acc, from_c, to_c, by_c) t(cutoff double precision, val double precision)
	LOOP
			ret.cutoff = row1.cutoff;
			ret.RMS = row1.val;
			return next ret;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;
  
 